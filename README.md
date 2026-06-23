# Homelab

![Last Commit](https://img.shields.io/github/last-commit/mkoelle/homelab?color=black&labelColor=black&label=last%20commit&logo=github&logoColor=cyan&style=flat-square)

This repository contains the setup, configurations, and automation scripts
I use to run and experiment with my homelab.
It's a personal workspace for learning and testing self-hosted services,
infrastructure-as-code, and network optimizations.
Although it's tailored to my needs,
you may find it useful as a reference or inspiration for a similar home setup.

## Important folders

- [docs/adrs](/docs/adrs/) - Architecture Decision Records
- [bootstrap](/bootstrap/) - Instructions for getting started
- [apps](/apps/) - Kubernetes applications
  - [core](/apps/core/) - Core applications

## Getting started

This setup expects at least two machines:

- A development machine used to issue commands and manage this repository
- A host machine that will run Kubernetes

### Development machine config

On macOS, install all required tools at once:

```sh
brew bundle
```

Otherwise install manually:

- **Management tools**
  - Kubectl — Kubernetes CLI ([install instructions](https://kubernetes.io/docs/tasks/tools/))
  - Talosctl — Talos cluster management ([install instructions](https://www.talos.dev/latest/usage/talosctl/))
  - Helm — Kubernetes package manager ([install instructions](https://helm.sh/docs/intro/install/))
- **Development tools**
  - Task — task runner ([install instructions](https://taskfile.dev/docs/installation))
  - Polaris — Kubernetes best practices auditor ([install instructions](https://polaris.docs.fairwinds.com/infrastructure-as-code/#installation))
  - Docker or Podman — container runtime ([Docker](https://docs.docker.com/engine/install/) / [Podman Desktop](https://podman-desktop.io/))
  - Freelens — k8s IDE ([install instructions](https://github.com/freelensapp/freelens))

### Host machine install and config

Initial setup of the environment is documented in [bootstrap](/bootstrap/README.md)
