# CI Patterns — home-ops GitLab runner

Last updated: 2026-04-27.

This runner enforces restricted Pod Security Standard at the namespace level
AND `runners.kubernetes.privileged = false` at the runner config level.
Privileged containers are structurally impossible. Build images via Kaniko
(see "Known limitation" below) or rootless Buildah. Document any exception
with a security review.

Container images push to the **cluster Harbor** at `harbor.melotic.dev`.
GitLab's built-in container registry is disabled — `$CI_REGISTRY*` variables
ARE NOT POPULATED. CI jobs use the **GitLab Harbor integration** to inject
Harbor credentials and registry coordinates, as described below.

---

## Harbor CI Integration — Operator Setup per GitLab Project

GitLab EE ships a built-in Harbor integration that auto-injects six CI/CD
variables into every job in the project:

| Variable           | Source                              |
|--------------------|-------------------------------------|
| `HARBOR_URL`       | Full URL (`https://harbor.melotic.dev`) |
| `HARBOR_HOST`      | Host without scheme (`harbor.melotic.dev`) |
| `HARBOR_OCI`       | OCI URL (`oci://harbor.melotic.dev`) |
| `HARBOR_PROJECT`   | Configured Harbor project name      |
| `HARBOR_USERNAME`  | Configured robot account name       |
| `HARBOR_PASSWORD`  | Robot account secret token (masked) |

### One-time setup per GitLab project

For each GitLab project that needs to push container images:

1. **Create a Harbor project.** In Harbor (`https://harbor.melotic.dev`),
   create a project. Typical convention: name the project after the GitLab
   group/namespace (e.g., GitLab namespace `acme` → Harbor project `acme`).
   Visibility: private. Storage quota: per-operator policy.
2. **Mint a Harbor robot account.** In the Harbor project →
   **Robot Accounts → New Robot Account**. Permissions: `push` AND `pull`
   on Repository, `pull` on Artifact (no admin, no delete). Expiration:
   per-operator policy (recommend 90 days; see rotation runbook below).
   Copy the generated secret token immediately — Harbor only shows it once.
3. **Store credentials in 1Password.** Create a 1Password item named
   `harbor-gitlab-<group>` (e.g. `harbor-gitlab-acme`) in the `Zion` vault
   with these fields:
   - `name`     → `robot$<project>+<robot-suffix>` (the robot account name)
   - `secret`   → the Harbor robot token
   - `project`  → Harbor project name
4. **Activate the GitLab Harbor integration on the project.** In GitLab UI →
   Project → **Settings → Integrations → Harbor**:
   - URL: `https://harbor.melotic.dev`
   - Project name: matches Harbor project (step 1)
   - Username: robot account name from step 2
   - Password: robot token from step 2
   - **Save changes**.
5. **Verify variable injection.** Run any pipeline; `$HARBOR_HOST`,
   `$HARBOR_PROJECT`, `$HARBOR_USERNAME`, `$HARBOR_PASSWORD` etc. are now
   available to all jobs in the project. No project-level CI/CD variables
   need to be set.

> **EE only.** The Harbor integration ships only in GitLab Enterprise
> Edition. The home-ops cluster runs `gitlab-webservice-ee:v18.11.1` so this
> is satisfied. CE installations must fall back to manual project-level
> CI/CD variables.

> **Trailing whitespace quirk.** GitLab stores `HARBOR_USERNAME` from the
> integration form with trailing whitespace from the input field. Pipelines
> MUST trim whitespace before constructing the docker auth payload — see the
> Kaniko sample below. Without trimming, Harbor returns `UNAUTHORIZED`.

### Robot token rotation runbook

Quarterly, OR on suspicion of leak:

1. Harbor → project → Robot Accounts → revoke old robot.
2. Mint new robot. Copy the new token.
3. Update the 1Password item (`harbor-gitlab-<group>`) `secret` field.
4. GitLab UI → Project → Settings → Integrations → Harbor → paste new
   token in `Password` field, **Save changes**.
5. Re-run any in-flight pipelines that failed during the swap.

Out of scope: automated provisioning of Harbor projects, robots, and the
GitLab integration record (e.g. via `terraform-provider-harbor`). Tracked
as a future improvement.

---

## Image build via Kaniko (with restricted-PSS workaround)

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
    # Trim whitespace from integration-injected vars (HARBOR_USERNAME has
    # trailing whitespace; harmless to trim HARBOR_PASSWORD too).
    - HARBOR_USERNAME_TRIM=$(printf '%s' "$HARBOR_USERNAME" | tr -d '[:space:]')
    - HARBOR_PASSWORD_TRIM=$(printf '%s' "$HARBOR_PASSWORD" | tr -d '[:space:]')
    - AUTH_B64=$(printf '%s:%s' "$HARBOR_USERNAME_TRIM" "$HARBOR_PASSWORD_TRIM" | base64 | tr -d '\n')
    - |
      cat > "$DOCKER_CONFIG/config.json" <<EOF
      { "auths": { "$HARBOR_HOST": { "auth": "$AUTH_B64" } } }
      EOF
    - /kaniko/executor
        --context "${CI_PROJECT_DIR}"
        --dockerfile "${CI_PROJECT_DIR}/Dockerfile"
        --destination "${HARBOR_HOST}/${HARBOR_PROJECT}/${CI_PROJECT_NAME}:${CI_COMMIT_SHA}"
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

### Known limitation: kaniko + restricted PSS

Kaniko unconditionally calls `chown` while unpacking image rootfs to the
build sandbox, which requires `CAP_CHOWN`. Restricted PSS strips ALL
capabilities, so kaniko fails image *build* (not auth, not push) with:

```
error building image: error building stage: failed to get filesystem from image:
chown /bin: operation not permitted
```

This is a fundamental kaniko design constraint — kaniko's docs state it
"must run as root inside the container," which is incompatible with our
namespace policy. The integration path (auth + push) is verified working;
only the build itself is gated.

**Workarounds** (none deployed in home-ops; tracked as a backlog item):

- **BuildKit rootless** (`moby/buildkit:rootless`) is purpose-built for
  restricted environments and uses user namespaces instead of capabilities.
  Recommended migration path.
- A **separate namespace with PSS=baseline** scoped only to ephemeral
  build pods (e.g. `gitlab-runner-builds`), with the runner controller
  remaining in `gitlab-runner` (PSS=restricted). Narrower deviation but
  more moving parts.
- Relaxing the `gitlab-runner` namespace PSS — **rejected** by repo
  conventions (`AGENTS.md` security context section).

Until that work lands, image-build pipelines using kaniko in this cluster
will succeed at auth/push but fail at unpack. Bring your own builder image
or wait for the migration.

## Image build via rootless Buildah (alternative)

```yaml
build-image-buildah:
  stage: build
  image: quay.io/buildah/stable:latest
  script:
    - set +x  # don't echo HARBOR_PASSWORD into job trace before login
    - HARBOR_USERNAME_TRIM=$(printf '%s' "$HARBOR_USERNAME" | tr -d '[:space:]')
    - HARBOR_PASSWORD_TRIM=$(printf '%s' "$HARBOR_PASSWORD" | tr -d '[:space:]')
    - echo "$HARBOR_PASSWORD_TRIM" | buildah login -u "$HARBOR_USERNAME_TRIM" --password-stdin "$HARBOR_HOST"
    - set -x
    - buildah --isolation=chroot bud -t "$HARBOR_HOST/$HARBOR_PROJECT/$CI_PROJECT_NAME:$CI_COMMIT_SHA" .
    - buildah push "$HARBOR_HOST/$HARBOR_PROJECT/$CI_PROJECT_NAME:$CI_COMMIT_SHA"
```

Buildah rootless has the same fundamental capability requirements as kaniko
under restricted PSS — listed here for documentation completeness only.

## Debugging caveats

- **Do NOT enable `CI_DEBUG_TRACE: "true"` on jobs that touch `HARBOR_PASSWORD`
  or any other Masked variable.** GitLab variable masking redacts values in
  normal job logs but does **not** cover xtrace output produced by
  `set -x` / `CI_DEBUG_TRACE`. Treating Masked vars as private requires
  keeping trace mode off (or wrapping sensitive blocks with `set +x` ... `set -x`).
- Prefer `--password-stdin` over inline `-p "$PASSWORD"` so the password
  never appears in the process argv (visible to other pods in the same node
  via `/proc` if PSS is relaxed).
- The Kaniko snippet above pipes `printf '%s:%s' "$HARBOR_USERNAME_TRIM" "$HARBOR_PASSWORD_TRIM"`
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
