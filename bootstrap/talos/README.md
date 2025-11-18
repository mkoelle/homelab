# Talos

Talos OS is a lightweight, immutable operating system built specifically for running Kubernetes clusters. Unlike traditional Linux distributions, Talos eliminates SSH access and package managers, focusing on security, automation, and consistency. Everything is managed through a secure API, making it ideal for declarative setups and GitOps workflows.
I use Talos OS as the backend for my homelab because it provides:

- Predictable Infrastructure: Immutable design ensures every node runs the same, reducing drift.
- API-Driven Management: No manual tinkering—perfect for automation and reproducibility.
- Security by Design: Minimal attack surface and strong cryptographic guarantees.
- Kubernetes-First Approach: Optimized for container orchestration without unnecessary OS overhead.

[TALOS image](https://factory.talos.dev/?arch=amd64&cmdline-set=true&extensions=-&extensions=siderolabs%2Fbtrfs&extensions=siderolabs%2Fnfsd&extensions=siderolabs%2Fzfs&platform=metal&secureboot=true&target=metal&version=1.10.6)
Schematic ID `e4452f8d06fe312ec9ebf81b8e970ab527c48f2dcd1e52b0153bd6954abf510b`

```yaml
customization:
    systemExtensions:
        officialExtensions:
            - siderolabs/btrfs
            - siderolabs/nfsd
            - siderolabs/zfs
```

## Initial Configuration

The following instructions and steps are for setting up or starting over with a blank machine, freshly provisioned.

```pwsh
$target = "motherbox.local"

# Generate Talos configuration for a bare metal cluster
# Creates the controlplane.yaml and worker.yaml files
# in addition to the talosconfig file in the current directory
talosctl gen config $target "https://${target}:6443"
# This will create the controlplane.yaml, talosconfig, and worker.yaml

# Apply the patch containing host ip mappings and the flag to 
# allow running workloads on control-plane nodes.
# (Needed because of running a single node instance)
talosctl gen config $target "https://${target}:6443" --config-patch `@patch.yaml --force

# Set the location of the saved config file
# This will save us from having to add --talosconfig ./talosconfig to every command
$env:TALOSCONFIG = (Get-Item "talosconfig").FullName

# Get the disks on the Talos node
# This will list the disks available on the node so we can pick one for the Talos installation
talosctl --nodes $target get disks --insecure
# if the desired disk is /dev/sda, then we can proceed with the installation
# otherwise, adjust the disk name accordingly in the controlplane.yaml and worker.yaml files

# Apply the Talos configuration to the control plane node
talosctl --nodes $target apply-config --file ./controlplane.yaml --insecure 
# The system will reboot automatically

# Once the node is back up, bootstrap the cluster to initialize etcd and the control plane
talosctl --nodes $target --endpoints $target bootstrap
# Dashboard will be angry for a few min as it configures

# we can now check the status of the node and list the nodes in the cluster
talosctl --nodes $target --endpoints $target services

# Finally, we can retrieve the kubeconfig file to interact with the Kubernetes cluster
talosctl --nodes $target --endpoints $target kubeconfig ./kubeconfig
# this creates the kubeconfig file

# Set the location of the saved config file
# This will save us from having to add --talosconfig ./talosconfig to every command
$env:KUBECONFIG = (Get-Item "kubeconfig").FullName
```

## Updates & Upgrades

```pwsh
$target = "motherbox.local"
$version = "v1.11.5"

# upgrade talos on the target machine
talosctl upgrade -n $target --image "ghcr.io/siderolabs/installer:${version}"

# upgrade kubernetes on the target machine
talosctl -n $target -e $target  upgrade-k8s
```

Try to keep the version of talosctl on the administrative machine in sync with the version of talos installed on the cluster machines

## References

- [Talos Storage Configuration Guide](https://www.talos.dev/v1.9/kubernetes-guides/configuration/storage/#nfs) - NFS and iSCSI storage options for Talos

- [Kubernetes Monitoring: A Complete Solution - Part 1 (Architecture)](https://itnext.io/kubernetes-monitoring-a-complete-solution-part-1-architecture-eb5b998658d5) - Comprehensive monitoring setup

- [Talos Kubernetes Setup](https://www.youtube.com/watch?v=HzNszgkVuaA) - Visual walkthrough of Talos installation and configuration

- [gruberdev/homelab](https://github.com/gruberdev/homelab) - Homelab setup reference
