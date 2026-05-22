# Kopia Azure Sync

Replicates the VolSync Kopia repository from `/var/nfs/shared/k8s/volsync` to Azure Blob storage at `nas-backup/k8s/volsync`.

The Azure SAS token comes from the 1Password item `nas-backup-azure`. Keep the token expiry and rotation date in that item and rotate before expiry; Prometheus alerts cover failed jobs and no successful sync for 48 hours.
