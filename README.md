# Homelab

![Last Commit](https://img.shields.io/github/last-commit/mkoelle/homelab?color=black&labelColor=black&label=last%20commit&logo=github&logoColor=cyan&style=flat-square)

This repo contains the setup, configurations, and automation scripts I use to manage and experiment with my own homelab environment. It's a personal space for learning and testing self-hosted services, infrastructure-as-code, and network optimization. While tailored to my needs, it can serve as inspiration or reference for anyone interested in building a similar setup at home.

## Important Folders

- [docs/adrs](/docs/adrs/) - Architecture Decision Records
- [setup](/setup/) - Instructions for getting started

## Getting started

I assume the use of at least two computers;
The development machine that will be used to issue commands and execute this repository,
and the host machine that will run kubernetes.

### Development machine config

The following tools need to be installed

- **Management**:
  - kubectl
  - talosctl
  - helm
- **Development**
  - [task](https://taskfile.dev/)

### Host machine install and config

Initial setup of the environment is documented in [Setup](/setup/README.md)
