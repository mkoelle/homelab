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

## Issue 2 — XFS I/O Error on STATE Partition (sda3)

**Symptom:** Install appeared to start but failed with:
```
ata3.00: error: { ICRC ABRT }
I/O error, dev sda, sector 4409402 op 0x1:(WRITE)
XFS (sda3): log recovery write I/O error at daddr 0x2 len 4096 error -5
XFS (sda3): log mount failed
[talos] controller failed block.MountController: failed to mount "STATE": input/output error
```

Same sector (`4409402`) failed on every attempt, regardless of:
- SATA cable (replaced — no change)
- SATA port (moved ata3 → ata4 — no change)
- Disk wipe (`wipe: true` added to patch.yaml — no change to error)

**Initial misdiagnosis:** Assumed failing drive. Ruled out after Debian 13 installed successfully to the same drive with no errors — including writes to the sector range containing LBA 4409402.

**Root cause (confirmed):** The drive had a prior Talos install with **SecureBoot + TPM-sealed LUKS encryption** on the STATE partition (`sda3`). The encrypted partition was not properly wiped before reinstall. Talos's XFS log write to the start of sda3 attempted to write over the locked LUKS container, which the drive or controller rejected.

The `ICRC ABRT` error is how the kernel's libata layer surfaces a write abort from the drive — not necessarily a physical CRC failure on the SATA bus.

**Fixes applied:**
1. Added `machine.install.wipe: true` to `patch.yaml` — forces the Talos installer to zero the partition table before install, clearing old LUKS metadata.
2. Sector 4409402 confirmed writeable from Debian via `hdparm --write-sector` (succeeded).

**Remaining issue:** Talos installer uses **NCQ DMA** writes; Debian's `hdparm` uses non-NCQ PIO. The sector write succeeds non-NCQ but fails under NCQ. `extraKernelArgs: [libata.force=noncq]` in `machine.install` is **invalid with SecureBoot UKI** — the setting `grubUseUKICmdline: true` (auto-set by SecureBoot factory images) is mutually exclusive with `extraKernelArgs`.

**Resolution:** Embed `libata.force=noncq` in the factory image schematic at `factory.talos.dev`. Add to the schematic YAML:
```yaml
customization:
  extraKernelArgs:
    - libata.force=noncq
  systemExtensions:
    officialExtensions:
      - siderolabs/btrfs
```
Download the resulting ISO, add to Ventoy, boot from it. The installer kernel will have NCQ disabled globally.

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

## Bootstrap State at End of Session

- Debian 13 installed on `sda` (temporary — to be wiped by Talos reinstall)
- Talos reinstall **not yet completed** — pending boot back to Talos USB
- `controlplane.yaml` and `talosconfig` generated (gitignored — store in Bitwarden)
- ArgoCD, Cilium, all apps not yet deployed

## Next Steps

1. Reboot `motherbox` to Talos USB (Ventoy)
2. Run apply-config from `bootstrap/talos/`:
   ```bash
   target="192.168.1.2"
   talosctl gen config motherbox.local "https://motherbox.local:6443" --config-patch @patch.yaml --force
   line=$(grep -n "^kind: HostnameConfig" controlplane.yaml | cut -d: -f1)
   sed -i '' "$((line-2)),\$d" controlplane.yaml
   talosctl --nodes $target apply-config --file ./controlplane.yaml --insecure
   ```
3. Wait for health, run bootstrap, get kubeconfig
4. Install Cilium (`bootstrap/cilium/README.md`)
5. Install ArgoCD and apply root application (`bootstrap/argocd/README.md`)
6. Order replacement drive
