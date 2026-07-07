# Talos

Talos OS is a lightweight, immutable operating system built specifically for running Kubernetes clusters. Unlike traditional Linux distributions, Talos eliminates SSH access and package managers, focusing on security, automation, and consistency. Everything is managed through a secure API.

## Factory Image

**Current schematic** (schematic ID `7538c8ece51ab4ebc4bd5557c4a5e9c886460596656155cd6a7d23356c2c0884`, [factory link](https://factory.talos.dev/?arch=amd64&platform=metal&schematic-id=7538c8ece51ab4ebc4bd5557c4a5e9c886460596656155cd6a7d23356c2c0884&secureboot=true&target=metal&version=1.13.5)):

```yaml
customization:
  extraKernelArgs:
    - libata.force=noncq
    - intel_iommu=off
  systemExtensions:
    officialExtensions:
      - siderolabs/intel-ucode
```

- `libata.force=noncq` — disables NCQ; changes `WRITE FPDMA QUEUED` to `WRITE DMA EXT`. Necessary but not sufficient on its own.
- `intel_iommu=off` — required: Intel Z97 VT-d IOMMU aborts DMA writes to the STATE partition XFS log sector for both NCQ and non-NCQ DMA. Without this, install always fails regardless of NCQ mode. Cannot be set via `extraKernelArgs` in `controlplane.yaml` — SecureBoot UKI ignores it. Must be baked into schematic.
- `intel-ucode` — Intel microcode updates (Spectre/Meltdown patches for Haswell).

Build the installer at [Talos Image Factory](https://factory.talos.dev) — select `metal`, `amd64`, `SecureBoot`, `v1.13.5`.

> If you change extensions or the Talos version, regenerate the schematic at factory.talos.dev and update the schematic ID here, in `controlplane.yaml` and `worker.yaml` installer images, and in the upgrade command below.

## Initial Setup

These steps assume a blank machine. Follow them in order — each step depends on the previous one completing successfully.

### Step 1 — Boot from Talos ISO

Write the factory image ISO to a USB drive and boot `motherbox` from it. The machine enters **maintenance mode**, which accepts unauthenticated `talosctl` connections.

```bash
# Verify the machine is in maintenance mode and reachable
talosctl --nodes motherbox.local get disks --insecure
```

Identify the target disk from the output. The `controlplane.yaml` uses a WWID selector:

```yaml
machine:
  install:
    diskSelector:
      wwid: naa.50025388a040deb7   # Samsung SSD 840 EVO 250GB
```

**Verify this WWID matches your disk before continuing.** Cross-reference the `Id` column from `get disks` output. Wrong WWID = wrong disk wiped.

### Step 2 — Generate Talos configuration

Run from the `bootstrap/talos/` directory. This generates `controlplane.yaml`, `worker.yaml`, and `talosconfig` — all gitignored because they contain cluster PKI private keys.

```powershell
$target = "motherbox.local"

# Single call — generates config with patch applied
talosctl gen config $target "https://${target}:6443" --config-patch @patch.yaml

# Set TALOSCONFIG so subsequent commands don't need --talosconfig flag
$env:TALOSCONFIG = (Get-Item "talosconfig").FullName
```

```bash
# bash equivalent
target="motherbox.local"
talosctl gen config $target "https://${target}:6443" --config-patch @patch.yaml
export TALOSCONFIG=$(pwd)/talosconfig

# Remove HostnameConfig document appended by Talos 1.13+ (conflicts with patch hostname)
line=$(grep -n "^kind: HostnameConfig" controlplane.yaml | cut -d: -f1)
sed -i '' "$((line-2)),\$d" controlplane.yaml
```

**Post-gen required edit:** Talos 1.13+ appends a `HostnameConfig: auto: stable` document to the generated file. This conflicts with `machine.network.hostname` from the patch and causes `apply-config` to fail with:

```
static hostname is already set in v1alpha1 config
```

Remove the appended section from `controlplane.yaml` before applying:

```bash
# HostnameConfig is appended at end of file; delete from its --- separator to EOF
line=$(grep -n "^kind: HostnameConfig" controlplane.yaml | cut -d: -f1)
sed -i '' "$((line-2)),\$d" controlplane.yaml
```

> `controlplane.yaml` in this repo is your live cluster config — gitignored, not a template. For a fresh machine, the above generates new PKI. **Store the generated `controlplane.yaml` and `talosconfig` somewhere safe** (e.g., Bitwarden) — losing them = losing cluster access.

### Step 3 — Apply configuration and bootstrap

```powershell
# Apply config — triggers install to disk and automatic reboot
talosctl --nodes $target apply-config --file ./controlplane.yaml --insecure

# Wait for node to come back up and API to be ready before proceeding
# This can take 3-5 minutes on first boot after install
talosctl --nodes $target --endpoints $target health --wait-timeout 10m

# Bootstrap etcd and the control plane — run EXACTLY ONCE
# Running this a second time on an already-bootstrapped cluster causes errors
talosctl --nodes $target --endpoints $target bootstrap

# Wait for Kubernetes control plane to become healthy
talosctl --nodes $target --endpoints $target health --wait-timeout 10m

# Verify services are running
talosctl --nodes $target --endpoints $target services

# Write kubeconfig to default location
talosctl --nodes $target --endpoints $target kubeconfig $HOME/.kube/config
```

### Step 4 — Verify cluster is up

```bash
kubectl get nodes
kubectl get pods -A
```

Both should show `Ready` / `Running` before proceeding to Cilium install.

## Upgrades

Keep `talosctl` version on the admin machine in sync with the cluster version.

```powershell
$target = "motherbox.local"
$version = "v1.13.5"

# Upgrade Talos OS
talosctl upgrade -n $target --image "factory.talos.dev/installer/7538c8ece51ab4ebc4bd5557c4a5e9c886460596656155cd6a7d23356c2c0884:${version}"

# Upgrade Kubernetes
talosctl -n $target -e $target upgrade-k8s
```

## References

- [Talos Storage Configuration Guide](https://www.talos.dev/v1.13/kubernetes-guides/configuration/storage/)
- [Talos Kubernetes Setup](https://www.youtube.com/watch?v=HzNszgkVuaA)
- [gruberdev/homelab](https://github.com/gruberdev/homelab)
