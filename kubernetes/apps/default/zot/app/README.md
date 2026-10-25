# zot

OCI registry used as the cluster's pull-through cache. Storage is a single NFS volume on
`construct` via the `nfs-construct` StorageClass, so the BoltDB metadata files under
`/var/lib/registry` depend on working NLM locks.

## zot crash-loops with a BoltDB error

Scale the StatefulSet to zero, delete the `*.db` files in the zot root on the export, then scale
back to one. zot rebuilds its metadata by walking storage at startup (`fastRestart` stays at its
default `false`), so the cached blobs survive.

## zot cannot start because its BoltDB lock is held after a node died permanently

NLM locks stay on the NAS until the client that held them reboots and `rpc.statd` sends its restart
notification. A node that dies for good never sends one, so clear that client's NLM locks on
`construct` (`sm-notify`/`rpc.statd` on the NAS, or reboot the NAS's lock state) and then restart
`zot-0`.
