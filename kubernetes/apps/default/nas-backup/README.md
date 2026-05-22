# NAS Backup

Copies non-Kopia shared NAS paths under `/var/nfs/shared/k8s` to Azure Blob storage at `nas-backup/k8s`.

Excluded paths:

- `/volsync/**`: VolSync's Kopia repository is replicated by `kopia-azure-sync`.
- `/pvc-*/**`: dynamic CSI NFS PVC directories are covered by workload-specific VolSync backup gates.
