Synology CSI (core-synology)
=================================

This folder contains a minimal kustomize overlay to deploy the Synology CSI
driver into the `core-synology` namespace.

Quick steps
-----------

1. Add the upstream repo as a git submodule (optional but useful to keep upstream manifests):

```sh
git submodule add https://github.com/zebernst/synology-csi-talos.git vendor/synology-csi-talos
git submodule update --init --recursive
```

2. Create a DSM client-info secret from `config/client-info-template.yml` (edit values first):

```sh
kubectl create secret -n core-synology generic client-info-secret --from-file=config/client-info.yml
```

3. If you build a custom Talos-compatible image, update the `image:` fields in `controller.yaml` and `node.yaml`.

4. Apply the kustomization:

```sh
kubectl apply -k apps/core/storage
```

Notes
-----
- Replace the `dsm` and `location` parameters in `storage-class.yaml` with your DSM IP and volume location.
- The manifests are intentionally minimal; consult the upstream repo for more advanced RBAC, PSPs, and snapshotter manifests.
