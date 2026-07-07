# MotherBox Reinstall Incident — June 2026

Findings and resolutions from a full Talos OS reinstall attempt on `motherbox.local`.

## Hardware

| Component       | Detail                                                                            |
| --------------- | --------------------------------------------------------------------------------- |
| Machine         | MotherBox (`192.168.1.2`)                                                         |
| CPU             | Intel (Z97 chipset, 9-series, Haswell)                                            |
| RAM             | 31 GiB                                                                            |
| SATA Controller | Intel 9 Series Chipset AHCI (`0000:00:1f.2`)                                      |
| Drive           | Samsung SSD 840 EVO 250GB — WWID `naa.50025388a040deb7`, serial `S1DBNSCF408526P` |
| Talos version   | 1.13.5                                                                            |

---

## Issue 1 — `static hostname is already set in v1alpha1 config`

**Symptom:** `talosctl apply-config` fails immediately:

```txt
error applying new configuration: rpc error: code = InvalidArgument desc = 1 error occurred:
  * static hostname is already set in v1alpha1 config
```

**Cause:** Talos 1.13+ appends a `HostnameConfig: auto: stable` document to `controlplane.yaml` during `gen config`. This conflicts with `machine.network.hostname` set in `patch.yaml`. Having both is invalid.

**Fix:** Remove the appended `HostnameConfig` block from `controlplane.yaml` after every `gen config` run:

```bash
line=$(grep -n "^kind: HostnameConfig" controlplane.yaml | cut -d: -f1)
sed -i '' "$((line-2)),\$d" controlplane.yaml
```

This one-liner is now embedded in the bash block in `bootstrap/talos/README.md`.

**Permanent fix:** Not possible — Talos always appends it. The sed strip is required every time.

---

## Issue 2 — XFS I/O Error on STATE Partition (Intel AHCI Controller / IOMMU DMA Fault)

**Symptom:** Install fails with one of two error forms depending on whether NCQ is disabled:

With NCQ enabled (standard ISO):

```txt
ata2.00: failed command: WRITE FPDMA QUEUED
I/O error, dev sdc, sector 4409402 op 0x1:(WRITE)
XFS (sdc3): log recovery write I/O error at daddr 0x2 len 4096 error -5
XFS (sdc3): log mount failed
[talos] controller failed block.MountController: failed to mount "STATE": input/output error
```

With `libata.force=noncq` (noncq-only schematic, July 7 2026):

```txt
ata4.00: failed command: WRITE DMA EXT
ata4.00: exception Emask 0x60 SAct 0x0 SErr 0x800 action 0x6 frozen
ata4.00: irq_stat 0x20000000, host bus error
I/O error, dev sdd, sector 4409416 op 0x1:(WRITE)
XFS (sdd3): log recovery write I/O error at daddr 0x10 len 4096 error -5
XFS (sdd3): log mount failed
[talos] controller failed block.MountController: failed to mount "STATE": openfs failed
```

Sectors `4409402`–`4409416` are where Talos places the STATE partition's XFS log. Error appeared on:

- Samsung SSD 840 EVO (`sda`/`sdd`) — prior Talos/LUKS install on disk
- WDC WD2003FYPS-2 2TB (`sdc`/`sdd`) — **no prior Talos install, no LUKS** (confirmed July 2026)

Same sector region, different drives, same AHCI controller, with and without NCQ. LUKS metadata was not the cause.

**Root cause:** The **Intel 9 Series Chipset AHCI controller** (`0000:00:1f.2`) produces host bus errors (`SErr 0x800` = `DIAGERR`, `Emask 0x60`) on DMA writes to this LBA under Talos's installer kernel. `libata.force=noncq` changes the command type from `WRITE FPDMA QUEUED` to `WRITE DMA EXT` but does not fix the underlying fault — the Intel VT-d IOMMU is aborting DMA address translation at this sector for both NCQ and non-NCQ DMA. Disabling the IOMMU entirely with `intel_iommu=off` is required.

**Why `extraKernelArgs` doesn't work:** Talos SecureBoot factory images set `grubUseUKICmdline: true`, which makes the bootloader read cmdline from the UKI binary rather than building it at boot. `machine.install.extraKernelArgs` in `controlplane.yaml` is ignored when this flag is set — the arg never reaches the kernel.

**Resolution:** Embed both `libata.force=noncq` and `intel_iommu=off` in the factory image schematic at `factory.talos.dev`:

```yaml
customization:
  extraKernelArgs:
    - libata.force=noncq
    - intel_iommu=off
  systemExtensions:
    officialExtensions:
      - siderolabs/intel-ucode
```

Select `metal`, `amd64`, `SecureBoot`, target Talos version. Download the ISO, replace the existing ISO on Ventoy, and reboot.

**Current schematic ID:** `7538c8ece51ab4ebc4bd5557c4a5e9c886460596656155cd6a7d23356c2c0884` ([factory link](https://factory.talos.dev/?arch=amd64&platform=metal&schematic-id=7538c8ece51ab4ebc4bd5557c4a5e9c886460596656155cd6a7d23356c2c0884&secureboot=true&target=metal&version=1.13.5))

> **Every reinstall on this machine requires this ISO.** A standard factory ISO, or one with only `libata.force=noncq`, will always fail at the STATE partition write step regardless of which SATA drive is the target.

**What does NOT fix it:**

- Changing SATA ports
- Replacing SATA cables
- Adding `machine.install.wipe: true` (wipe runs fine; XFS log write fails after)
- Adding `extraKernelArgs` to `controlplane.yaml` (ignored by UKI bootloader)
- `libata.force=noncq` alone (changes command type, host bus error persists)

---

## Issue 3 — `certSANs: []` in Generated Config

**Symptom:** After applying new config, `talosctl` connections fail with:

```txt
x509: certificate is valid for MotherBox, not motherbox.local
```

**Cause:** `talosctl gen config` generates `certSANs: []` by default. After install, the machine API cert only includes the auto-derived hostname (title-cased, e.g. `MotherBox`) plus loopback IPs. Hostnames and IPs we use for `talosctl` are missing.

**Fix:** Added `machine.certSANs` to `patch.yaml`:

```yaml
machine:
  certSANs:
    - motherbox
    - motherbox.local
    - 192.168.1.2
```

---

## Drive Health (SMART — June 2026)

Obtained from Debian 13 via `smartctl -a /dev/sda`:

| Attribute               | Value          | Notes                                      |
| ----------------------- | -------------- | ------------------------------------------ |
| Overall health          | PASSED         |                                            |
| Power_On_Hours          | 109,956        | **~12.5 years continuous**                 |
| Reallocated_Sector_Ct   | 64             | 64 bad blocks remapped to spare pool       |
| Uncorrectable_Error_Cnt | 128            | Errors ECC could not correct over lifetime |
| Wear_Leveling_Count     | 184 (84%)      | Remaining wear budget                      |
| Total_LBAs_Written      | 94,364,528,722 | ~44 TB written                             |
| ATA Error Log           | No Errors      | Recent errors not logged                   |

**Assessment:** Drive is old but still PASSED. With 64 remapped sectors and 128 lifetime uncorrectable errors, it is degrading. Expect further sector failures. Plan replacement before next reinstall.

**Recommendation:** Replace with a modern NVMe SSD (~$40 for 500GB). If motherboard lacks M.2, use a PCIe adapter. Do not rely on this drive for a production homelab without monitoring.

---

## Changes Made to Repository

| File                         | Change                                                                                                                                   |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `bootstrap/talos/patch.yaml` | Added `install.wipe: true`, `machine.certSANs`, `cluster.apiServer.certSANs`                                                             |
| `bootstrap/talos/patch.yaml` | Added `install.extraKernelArgs: [libata.force=noncq]` (NCQ disable — precautionary, kept)                                                |
| `bootstrap/talos/README.md`  | Added post-gen `sed` one-liner to strip `HostnameConfig`; updated to v1.13.5; added HostnameConfig conflict note with exact error string |
| `bootstrap/README.md`        | Updated `talosctl` version to v1.13.5                                                                                                    |
| `bootstrap/talos/README.md`  | Removed unused extensions (`nfsd`, `zfs`) from factory image schematic                                                                   |

---

## Bootstrap State at End of Session (updated July 7 2026)

- Install on WDC WD2003FYPS-2 2TB (`sdc`/`sdd`, WWID `naa.50014ee2afc640d2`) attempted twice — failed both times
  - First attempt: standard ISO — `WRITE FPDMA QUEUED` NCQ abort at sector 4409402
  - Second attempt: noncq-only ISO (`3683263dbb2b4b1898ea2a6312d1dd2549b9752505201da1b07f71a9538886c4`) — `WRITE DMA EXT` host bus error at sector 4409416 — noncq confirmed working, IOMMU DMA abort persists
- Root cause updated: Intel VT-d IOMMU aborts DMA at this LBA for both NCQ and non-NCQ writes; `intel_iommu=off` required
- `controlplane.yaml` disk selector: `wwid: naa.50014ee2afc640d2` (WD 2TB) — correct, no regen needed
- `controlplane.yaml` and `talosconfig` generated (gitignored — store in Bitwarden)
- Ventoy ISO must be replaced with new schematic including `intel_iommu=off` before next attempt
- ArgoCD, Cilium, all apps not yet deployed

## Next Steps

1. Build new factory ISO at factory.talos.dev with schematic:

   ```yaml
   customization:
     extraKernelArgs:
       - libata.force=noncq
       - intel_iommu=off
     systemExtensions:
       officialExtensions:
         - siderolabs/intel-ucode
   ```

   Select `metal`, `amd64`, `SecureBoot`, `v1.13.5`. Update schematic ID in `bootstrap/talos/README.md`.

2. Replace ISO on Ventoy, reboot `motherbox` from it
3. Run apply-config from `bootstrap/talos/`:

   ```bash
   cd bootstrap/talos
   export TALOSCONFIG=$(pwd)/talosconfig
   target="motherbox.local"
   talosctl --nodes $target apply-config --file ./controlplane.yaml --insecure
   ```

   (`controlplane.yaml` already has correct disk selector — no need to regen unless PKI is lost)

4. Wait for health, run bootstrap, get kubeconfig:

   ```bash
   talosctl --nodes $target --endpoints $target health --wait-timeout 10m
   talosctl --nodes $target --endpoints $target bootstrap
   talosctl --nodes $target --endpoints $target health --wait-timeout 10m
   talosctl --nodes $target --endpoints $target kubeconfig $HOME/.kube/config
   ```

5. Install Cilium (`bootstrap/cilium/README.md`)
6. Install ArgoCD and apply root application (`bootstrap/argocd/README.md`)
7. Order replacement drive for Samsung SSD 840 (degraded — see Drive Health section)
