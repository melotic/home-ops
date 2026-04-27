# CI Patterns — home-ops GitLab runner

Last updated: 2026-04-25.

This runner enforces restricted Pod Security Standard at the namespace level
AND `runners.kubernetes.privileged = false` at the runner config level.
Privileged containers are structurally impossible. Build images via Kaniko or
rootless Buildah. Document any exception with a security review.

Container images push to the **cluster Harbor** at `harbor.melotic.dev`.
GitLab's built-in container registry is disabled — `$CI_REGISTRY*` variables
ARE NOT POPULATED. CI jobs use the Harbor group-level CI/CD variables
described below.

---

## Harbor CI Integration — Operator One-Time Setup per GitLab Group

For each GitLab top-level group that needs to push container images, the
operator performs this 4-step setup ONCE:

1. **Create a Harbor project.** In Harbor (`https://harbor.melotic.dev`),
   create a project whose name matches the GitLab top-level group name
   exactly (e.g., GitLab group `acme` → Harbor project `acme`). Visibility:
   private. Storage quota: per-operator policy.
2. **Mint a Harbor robot account.** In the Harbor project →
   **Robot Accounts → New Robot Account**. Name suffix: `ci`
   (so the full account name becomes `robot$<group>+ci`, e.g.
   `robot$acme+ci`). Permissions: `push` and `pull` on Repository,
   `pull` on Artifact (no admin, no delete). Expiration: per-operator
   policy (recommend 90 days; see rotation runbook below). Copy the
   generated secret token immediately — Harbor only shows it once.
3. **Store credentials in 1Password.** Create a new 1Password item named
   `harbor-gitlab-<group>` (e.g. `harbor-gitlab-acme`) with these fields:
   - `name`         → `robot$<group>+ci` (the robot account name)
   - `secret`       → the Harbor robot token
   - `registry`     → `harbor.melotic.dev` (constant)
   - `image_prefix` → `harbor.melotic.dev/<group>` (e.g. `harbor.melotic.dev/acme`)
4. **Set GitLab group-level CI/CD variables.** In GitLab UI → Group →
   **Settings → CI/CD → Variables → Add variable**. Add four group-scoped
   variables (NOT project-scoped — that's the whole point of this model):

   | Key                   | Value (from 1Password)        | Type     | Flags                  |
   |-----------------------|-------------------------------|----------|------------------------|
   | `HARBOR_REGISTRY`     | `harbor.melotic.dev`          | Variable | Protected (optional)   |
   | `HARBOR_USER`         | `robot$<group>+ci`            | Variable | Protected (optional)   |
   | `HARBOR_PASSWORD`     | <robot token>                 | Variable | **Masked + Protected** |
   | `HARBOR_IMAGE_PREFIX` | `harbor.melotic.dev/<group>`  | Variable | Protected (optional)   |

   `Masked` requires the token to satisfy GitLab's masking rules
   (≥ 8 chars, base64-friendly alphabet) — Harbor robot tokens do.
   `Protected` restricts the variable to protected branches/tags only;
   set per the operator's branch-protection policy.

That's it. Every project in that GitLab group automatically inherits
these four variables and CI jobs can push to Harbor with no per-project
secret setup.

### Robot token rotation runbook

Quarterly, OR on suspicion of leak:

1. Harbor → project → Robot Accounts → revoke old robot.
2. Mint new robot (same name + `ci` suffix is fine — Harbor allows reuse
   after revoke; if not, append a numeric suffix and update everywhere).
3. Update 1Password item `harbor-gitlab-<group>` field `secret`.
4. Update GitLab group CI/CD variable `HARBOR_PASSWORD` (paste new token).
5. Re-run any in-flight pipelines that failed during the swap.

Out of scope: automated provisioning of Harbor projects and robots
(e.g. via `terraform-provider-harbor`). Tracked as a future improvement.

---

## Image build via Kaniko (recommended)

```yaml
build-image:
  stage: build
  image:
    name: gcr.io/kaniko-project/executor:v1.23.2-debug
    entrypoint: [""]
  variables:
    # The kaniko image's /kaniko directory is root-owned 0755 and unwritable
    # by the build pod's uid 1000 (enforced by namespace PSS=restricted +
    # pod_security_context.run_as_user=1000). Redirect Docker auth to /tmp,
    # which the runner mounts as an emptyDir writable by uid 1000.
    # Kaniko's executor honors $DOCKER_CONFIG ahead of its /kaniko/.docker
    # default discovery path. Note: the gitlab-runner config also exports
    # this same DOCKER_CONFIG default at the runner level (defense in depth)
    # so jobs that omit this `variables:` block still work.
    DOCKER_CONFIG: "/tmp/.docker"
  script:
    - mkdir -p "$DOCKER_CONFIG"
    - |
      cat > "$DOCKER_CONFIG/config.json" <<EOF
      { "auths": { "$HARBOR_REGISTRY": { "auth": "$(printf '%s:%s' "$HARBOR_USER" "$HARBOR_PASSWORD" | base64)" } } }
      EOF
    - /kaniko/executor
        --context "${CI_PROJECT_DIR}"
        --dockerfile "${CI_PROJECT_DIR}/Dockerfile"
        --destination "${HARBOR_IMAGE_PREFIX}/${CI_PROJECT_NAME}:${CI_COMMIT_SHA}"
```

Use the `:debug` tag (has `/busybox/sh`).

**Why `DOCKER_CONFIG=/tmp/.docker` and not `/kaniko/.docker`:** the runner
namespace enforces restricted Pod Security Standard, so all build pods must
run as non-root (`run_as_user=1000`). The kaniko image's `/kaniko` directory
is root-owned `0755`, so writing the auth config to its default location
fails with `Permission denied`. `/tmp` is mounted as a per-job emptyDir with
the pod's `fs_group=1000`, giving uid 1000 write access. Kaniko's executor
loads credentials from `$DOCKER_CONFIG` if set, then `$HOME/.docker`, then
`/kaniko/.docker` — so the redirect is transparent to the rest of the build.

## Image build via rootless Buildah (alternative)

```yaml
build-image-buildah:
  stage: build
  image: quay.io/buildah/stable:latest
  script:
    - set +x  # don't echo HARBOR_PASSWORD into job trace before login
    - echo "$HARBOR_PASSWORD" | buildah login -u "$HARBOR_USER" --password-stdin "$HARBOR_REGISTRY"
    - set -x
    - buildah --isolation=chroot bud -t "$HARBOR_IMAGE_PREFIX/$CI_PROJECT_NAME:$CI_COMMIT_SHA" .
    - buildah push "$HARBOR_IMAGE_PREFIX/$CI_PROJECT_NAME:$CI_COMMIT_SHA"
```

## Debugging caveats

- **Do NOT enable `CI_DEBUG_TRACE: "true"` on jobs that touch `HARBOR_PASSWORD`
  or any other Masked variable.** GitLab variable masking redacts values in
  normal job logs but does **not** cover xtrace output produced by
  `set -x` / `CI_DEBUG_TRACE`. Treating Masked vars as private requires
  keeping trace mode off (or wrapping sensitive blocks with `set +x` ... `set -x`).
- Prefer `--password-stdin` over inline `-p "$PASSWORD"` so the password
  never appears in the process argv (visible to other pods in the same node
  via `/proc` if PSS is relaxed).
- The Kaniko snippet above pipes `printf '%s:%s' "$HARBOR_USER" "$HARBOR_PASSWORD"`
  through `base64`. The literal password is on stdin only, but the surrounding
  heredoc is a shell command — wrap with `set +x` before the heredoc if the
  job otherwise enables xtrace.

## FORBIDDEN patterns — will fail at admission

```yaml
# BLOCKED — `services: docker:dind` requires privileged=true.
services:
  - docker:dind

# BLOCKED — random container demanding host capabilities.
variables:
  KUBERNETES_PRIVILEGED: "true"   # ignored by runner; namespace PSS rejects regardless
```

## Limits

- Default per-job pod resources: 100m / 256Mi requests; 1 / 1Gi limits.
  Override per-pipeline if needed via standard GitLab CI vars
  (`KUBERNETES_CPU_REQUEST`, etc.).
- Runner controller `concurrent: 4` — at most 4 simultaneous CI pods cluster-wide.
- `helper_image` is the chart-default stock `gitlab/gitlab-runner-helper`. No
  kitchen-sink image. If a job needs `kubectl` / `flux` / `helm`, the JOB
  image brings them.
- `$CI_REGISTRY*` predefined variables are UNPOPULATED (GitLab built-in
  registry disabled). Always use `$HARBOR_*` variables; jobs that reference
  `$CI_REGISTRY*` will silently push nowhere.
