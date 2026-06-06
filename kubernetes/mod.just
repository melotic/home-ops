set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[private]
default:
    just --list kube

[doc('Force-reconcile Flux resources of a kind [resource=hr|ks|gitrepo|ocirepo|es]')]
[script]
sync resource:
    test -f "$KUBECONFIG"
    kubectl get {{ resource }} --no-headers -A | while read -r ns name _; do
        kubectl -n "$ns" annotate --field-manager flux-client-side-apply --overwrite {{ resource }} "$name" \
            "force-sync=$(date +%s)" \
            "reconcile.fluxcd.io/requestedAt=$(date +%s)" \
            "reconcile.fluxcd.io/forceAt=$(date +%s)"
    done

[doc('Prune pods in Failed, Pending, or Succeeded state')]
[script]
prune-pods:
    test -f "$KUBECONFIG"
    for phase in Failed Pending Succeeded; do
        kubectl delete pods -A --field-selector "status.phase=$phase" --ignore-not-found=true
    done

[doc('Browse a PVC with an ephemeral Alpine pod [ns, claim required]')]
browse-pvc ns claim:
    kubectl run -n {{ ns }} browse-pvc-{{ claim }} -it --rm --restart=Never \
        --image=mirror.gcr.io/alpine:latest \
        --overrides='{"spec":{"containers":[{"name":"browse-pvc-{{ claim }}","image":"mirror.gcr.io/alpine:latest","stdin":true,"tty":true,"command":["/bin/sh"],"workingDir":"/mnt","volumeMounts":[{"mountPath":"/mnt","name":"data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"{{ claim }}"}}]}}'

[doc('Debug a node with an ephemeral privileged pod [node=required]')]
[script]
debug-node node:
    test -f "$KUBECONFIG"
    trap 'kubectl delete pod -n default -l app.kubernetes.io/managed-by=kubectl-debug --field-selector spec.nodeName={{ node }} --ignore-not-found --wait=false' EXIT
    kubectl debug node/{{ node }} -n default -it --image=mirror.gcr.io/alpine:latest --profile=sysadmin
