# MotherBox Reinstall Incident — June 2026

Findings and resolutions from a full Talos OS reinstall attempt on `motherbox.local`.

## Hardware

| Component | Detail |
|---|---|
| Machine | MotherBox (`192.168.1.2`) |
| CPU | Intel (Z97 chipset, 9-series, Haswell) |
| RAM | 31 GiB |
| SATA Controller | Intel 9 Series Chipset AHCI (`0000:00:1f.2`) |
| Drive | Samsung SSD 840 EVO 250GB — WWID `naa.50025388a040deb7`, serial `S1DBNSCF408526P` |
| Talos version | 1.13.5 |

---

## Issue 1 — `static hostname is already set in v1alpha1 config`

**Symptom:** `talosctl apply-config` fails immediately:
```
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

## Issue 2 — XFS I/O Error on STATE Partition (NCQ DMA, Intel AHCI Controller)

**Symptom:** Install fails with:
```
ata2.00: failed command: WRITE FPDMA QUEUED
I/O error, dev sdc, sector 4409402 op 0x1:(WRITE)
XFS (sdc3): log recovery write I/O error at daddr 0x2 len 4096 error -5
XFS (sdc3): log mount failed
[talos] controller failed block.MountController: failed to mount "STATE": input/output error
```

Sector `4409402` is where Talos places the STATE partition's XFS log. Same error appeared on:
- Samsung SSD 840 EVO (`sda`/`sdd`) — prior Talos/LUKS install on disk
- WDC WD2003FYPS-2 2TB (`sdc`) — **no prior Talos install, no LUKS** (confirmed July 2026)

Same sector, different drives, same AHCI controller. LUKS metadata was not the cause.

**Root cause:** The **Intel 9 Series Chipset AHCI controller** (`0000:00:1f.2`) rejects NCQ DMA writes (`WRITE FPDMA QUEUED`) to this LBA under Talos's installer kernel. Debian writes the same sector successfully because `hdparm --write-sector` uses non-NCQ PIO — not because the sector or drive is healthy. The `ICRC ABRT` / host bus error is a controller-level NCQ abort, not a physical media failure.

**Why `extraKernelArgs` doesn't work:** Talos SecureBoot factory images set `grubUseUKICmdline: true`, which makes the bootloader read cmdline from the UKI binary rather than building it at boot. `machine.install.extraKernelArgs` in `controlplane.yaml` is ignored when this flag is set — the arg never reaches the kernel.

**Resolution:** Embed `libata.force=noncq` directly in the factory image schematic at `factory.talos.dev`:
```yaml
customization:
  extraKernelArgs:
    - libata.force=noncq
  systemExtensions:
    officialExtensions:
      - siderolabs/intel-ucode
```
Select `metal`, `amd64`, `SecureBoot`, target Talos version. Download the ISO, replace the existing ISO on Ventoy, and reboot. The installer kernel will have NCQ disabled for all SATA devices on the controller.

**Current schematic ID:** `3683263dbb2b4b1898ea2a6312d1dd2549b9752505201da1b07f71a9538886c4` ([factory link](https://factory.talos.dev/?arch=amd64&platform=metal&schematic-id=3683263dbb2b4b1898ea2a6312d1dd2549b9752505201da1b07f71a9538886c4&secureboot=true&target=metal&version=1.13.5))

> **Every reinstall on this machine requires this ISO.** A standard factory ISO without `libata.force=noncq` will always fail at the STATE partition write step, regardless of which SATA drive is the target.

**What does NOT fix it:**
- Changing SATA ports
- Replacing SATA cables
- Adding `machine.install.wipe: true` (wipe runs fine; XFS log write fails after)
- Adding `extraKernelArgs` to `controlplane.yaml` (ignored by UKI bootloader)

---

## Issue 3 — `certSANs: []` in Generated Config

**Symptom:** After applying new config, `talosctl` connections fail with:
```
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

| Attribute | Value | Notes |
|---|---|---|
| Overall health | PASSED | |
| Power_On_Hours | 109,956 | **~12.5 years continuous** |
| Reallocated_Sector_Ct | 64 | 64 bad blocks remapped to spare pool |
| Uncorrectable_Error_Cnt | 128 | Errors ECC could not correct over lifetime |
| Wear_Leveling_Count | 184 (84%) | Remaining wear budget |
| Total_LBAs_Written | 94,364,528,722 | ~44 TB written |
| ATA Error Log | No Errors | Recent errors not logged |

**Assessment:** Drive is old but still PASSED. With 64 remapped sectors and 128 lifetime uncorrectable errors, it is degrading. Expect further sector failures. Plan replacement before next reinstall.

**Recommendation:** Replace with a modern NVMe SSD (~$40 for 500GB). If motherboard lacks M.2, use a PCIe adapter. Do not rely on this drive for a production homelab without monitoring.

---

## Changes Made to Repository

| File | Change |
|---|---|
| `bootstrap/talos/patch.yaml` | Added `install.wipe: true`, `machine.certSANs`, `cluster.apiServer.certSANs` |
| `bootstrap/talos/patch.yaml` | Added `install.extraKernelArgs: [libata.force=noncq]` (NCQ disable — precautionary, kept) |
| `bootstrap/talos/README.md` | Added post-gen `sed` one-liner to strip `HostnameConfig`; updated to v1.13.5; added HostnameConfig conflict note with exact error string |
| `bootstrap/README.md` | Updated `talosctl` version to v1.13.5 |
| `bootstrap/talos/README.md` | Removed unused extensions (`nfsd`, `zfs`) from factory image schematic |

---

## Bootstrap State at End of Session (updated July 2026)

- Install on WDC WD2003FYPS-2 2TB (`sdc`, WWID `naa.50014ee2afc640d2`) attempted and failed — same NCQ error
- `controlplane.yaml` updated: disk selector changed from `/dev/sda` to `diskSelector.wwid: naa.50014ee2afc640d2`
- Ventoy ISO does **not** have `libata.force=noncq` — must rebuild before retrying
- `controlplane.yaml` and `talosconfig` generated (gitignored — store in Bitwarden)
- ArgoCD, Cilium, all apps not yet deployed

## Next Steps

1. ✅ Factory ISO built — schematic ID `3683263dbb2b4b1898ea2a6312d1dd2549b9752505201da1b07f71a9538886c4` (noncq + intel-ucode, SecureBoot)
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
