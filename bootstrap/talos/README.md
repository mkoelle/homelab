# Talos

Talos OS is a lightweight, immutable operating system built specifically for running Kubernetes clusters. Unlike traditional Linux distributions, Talos eliminates SSH access and package managers, focusing on security, automation, and consistency. Everything is managed through a secure API.

## Factory Image

**Current schematic** (schematic ID `7538c8ece51ab4ebc4bd5557c4a5e9c886460596656155cd6a7d23356c2c0884`, [factory link](https://factory.talos.dev/?arch=amd64&platform=metal&schematic-id=7538c8ece51ab4ebc4bd5557c4a5e9c886460596656155cd6a7d23356c2c0884&secureboot=true&target=metal&version=1.14.1), [PXE URL](https://pxe.factory.talos.dev/pxe/7538c8ece51ab4ebc4bd5557c4a5e9c886460596656155cd6a7d23356c2c0884/v1.14.1/metal-amd64-secureboot)):

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

Build the installer at [Talos Image Factory](https://factory.talos.dev) — select `metal`, `amd64`, `SecureBoot`, `v1.14.1`.

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
      wwid: naa.50025388a040deb7 # Samsung SSD 840 EVO 250GB
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
```

**Post-gen required edits.** Talos 1.14 auto-appends two documents that conflict with this repo's patched config, and there's one default value `patch.yaml` cannot override (see below). All three must be fixed by hand after every `gen config` run — `apply-config` will reject the config, or silently keep an unwanted default, otherwise.

The generated config also contains Talos's default `KubeAuditPolicyConfig`
(Metadata for all resources). Keep the `KubeAuditPolicyConfig` in `patch.yaml`
when generating or updating the live config: it adds `RequestResponse` logging
for Secrets before the Metadata fallback. Without that patch, audit logs record
Secret reads but not their returned contents. The live `controlplane.yaml` is
gitignored, so the tracked patch is the reproducible source for this policy.

> ⚠️ **Do not delete "from this document to EOF".** Neither appended document is guaranteed to be last — on Talos 1.14, `UnattendedInstallConfig` is *not* the last document, and deleting to EOF silently destroys every `Kube*Config` document after it (including `KubeClusterConfig`, `KubeNodeConfig`, `KubeletConfig` — the ones that make kubelet start at all). Always delete only from the document's own `---` separator to the *next* `---`, never to EOF. This exact mistake cost a multi-hour bootstrap incident on 2026-09-21.

```bash
# Remove UnattendedInstallConfig (conflicts with patch.yaml's machine.install block)
# and HostnameConfig (conflicts with machine.network.hostname) -- bounded deletes only.
for kind in UnattendedInstallConfig HostnameConfig; do
  kind_line=$(grep -n "^kind: $kind" controlplane.yaml | cut -d: -f1)
  [ -z "$kind_line" ] && continue
  start=$((kind_line - 2))
  end=$(awk -v s=$((kind_line + 1)) 'NR>=s && /^---$/{print NR; exit}' controlplane.yaml)
  end=$((end - 1))
  sed -i '' "${start},${end}d" controlplane.yaml
done

# Clear the default control-plane NoSchedule taint (KubeNodeConfig) -- needed so
# this single-node cluster can schedule workloads. patch.yaml cannot express this:
# config-patch uses RFC7386-style merge, and neither `taints: {}` nor nulling the
# specific key nor `$patch: replace` clears a map entry within a document (only
# whole-document `$patch: delete` works) -- confirmed by test-generation, not a guess.
awk '
  /^taints:$/ { print "taints: {}"; skip=1; next }
  skip && /^    /  { next }
  { skip=0; print }
' controlplane.yaml > controlplane.yaml.tmp && mv controlplane.yaml.tmp controlplane.yaml
```

Each conflict, if left unfixed:

```txt
# UnattendedInstallConfig present alongside patch.yaml's machine.install block:
error applying configuration: ... UnattendedInstallConfig config is incompatible with v1alpha1 config (.machine.install)

# HostnameConfig present alongside patch.yaml's machine.network.hostname:
error applying configuration: ... static hostname is already set in v1alpha1 config
```

The taint isn't a hard failure — kubelet just won't schedule workloads on the single control-plane node until it's cleared.

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
$version = "v1.14.1"

# Upgrade Talos OS
talosctl upgrade -n $target --image "factory.talos.dev/installer/7538c8ece51ab4ebc4bd5557c4a5e9c886460596656155cd6a7d23356c2c0884:${version}"

# Upgrade Kubernetes
talosctl -n $target -e $target upgrade-k8s
```

## References

- [Talos Storage Configuration Guide](https://www.talos.dev/v1.13/kubernetes-guides/configuration/storage/)
- [Talos Kubernetes Setup](https://www.youtube.com/watch?v=HzNszgkVuaA)
- [gruberdev/homelab](https://github.com/gruberdev/homelab)
