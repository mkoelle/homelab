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
- [setup](/setup/) - Instructions for getting started

## Getting started

This setup expects at least two machines:

- A development machine used to issue commands and manage this repository
- A host machine that will run Kubernetes

### Development machine config

The following tools need to be installed

- **Management tools**
  - Kubectl — Kubernetes CLI ([install instructions](https://kubernetes.io/docs/tasks/tools/))
  - Talosctl — Talos cluster management ([install instructions](https://www.talos.dev/latest/usage/talosctl/))
  - Helm — Kubernetes package manager ([install instructions](https://helm.sh/docs/intro/install/))
- **Development tools**
  - Task — task runner ([install instructions](https://taskfile.dev/docs/installation))
  - Docker — container runtime ([install instructions](https://docs.docker.com/engine/install/))

### Host machine install and config

Initial setup of the environment is documented in [Setup](/setup/README.md)
