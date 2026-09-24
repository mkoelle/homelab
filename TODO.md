# Future projects

## Tools to investigate

Ranked highest-to-lowest fit for this specific setup (single-node Talos
cluster, GitOps via ArgoCD, personal/single-user use). Items already running
live, or made redundant by what's already running, have been removed --
see the note at the top of each affected category.

### Infrastructure, Networking & Monitoring

- **Authentication & Identity** -- solved for the current app set.
  [Zitadel](apps/core/zitadel) is live (native OIDC for ArgoCD/Grafana,
  oauth2-proxy for Hubble/Alloy/OpenCost/Homepage, plus Google Sign-In).
  Filebrowser authentication remains a tracked gap. Authelia and
  PocketID were both evaluated and superseded by it this cycle; dropped the
  rest of the category (Authentik, TinyAuth, Traefik OIDC Plugin, VoidAuth,
  dex) as redundant with a working solution already in place.
- **Monitoring & Analytics** -- Grafana, VictoriaMetrics, Loki, Alloy,
  Alertmanager, Uptime Kuma, and OpenCost are deployed under `apps/core/`.
  Prometheus's role is covered by VictoriaMetrics; Alloy is the sole
  scraper/shipper. Dropped Fluentbit (superseded by Alloy) and Zabbix
  (enterprise-scale distributed monitoring is overkill for one node).
  1. [Beszel](https://www.beszel.dev/) -- lightweight host-level resource
     monitoring, low overhead, complements the cluster-level metrics already
     collected.
  2. Discover-tab-style log search (field facets, histogram, one-click
     filters) -- solved. Evaluated OpenObserve for this, dropped it: its
     official Helm chart is HA-only (mandatory Postgres + S3-compatible
     object store), and its OSS edition has no SSO at all (Enterprise/Cloud
     only) -- a real loss on a cluster where every other UI is behind
     Zitadel. [Grafana Logs Drilldown](https://grafana.com/grafana/plugins/grafana-lokiexplore-app/)
     (official Grafana Labs plugin, on the catalog) gives the same UX on top
     of the existing Loki setup, inheriting Grafana's Zitadel SSO for free.
  3. [Umami](https://umami.is/) -- only relevant if self-hosting a personal
     site/blog with visitors to track.
  4. [Dozzle](https://dozzle.dev/) -- quick ad-hoc container log tailing;
     largely redundant now that Loki/Grafana cover logs, kept for the
     convenience of a zero-query live view.
- **Networking & Tunnels**
  1. [Tailscale](https://tailscale.com/) -- highest value-to-effort: mesh VPN
     for remote access to the homelab without exposing anything publicly.
  2. [OPNsense](https://opnsense.org/) -- would replace the current
     FreshTomato router; high value but a hardware/migration project, not a
     cluster app.
  3. [Pangolin](https://github.com/fosrl/pangolin) -- self-hosted tunnel for
     publicly exposing services under your own domain; overlaps partly with
     what Cilium Gateway API + cert-manager already do for LAN/TLS, only
     adds value if public (not just LAN) exposure is actually wanted.
  4. [Gluetun](https://github.com/qdm12/gluetun) -- VPN client container for
     routing a specific service's traffic through a VPN provider; niche,
     mainly relevant for download clients.
- **Password Management** -- dropped
  [Passbolt](https://www.passbolt.com/): it's a team-collaboration password
  manager, no fit for a single-user homelab, and Bitwarden Secrets Manager
  already covers infra-secret needs.
  1. [Vaultwarden](https://github.com/dani-garcia/vaultwarden) -- self-hosted
     personal password vault, if moving off Bitwarden's cloud is ever wanted.
- **Remote Access**
  1. [Rustdesk](https://rustdesk.com/) -- self-hosted remote desktop.

### Productivity & Knowledge Management

- **Finance**
  1. [Actual Budget](https://github.com/actualbudget/actual) -- local-first
     personal finance, clear direct fit.
  2. [Shkeeper](https://github.com/vsys-host/shkeeper.io) -- self-hosted
     crypto payment *processor*; this is a merchant/business tool, not a
     personal-finance one -- low fit unless there's an actual storefront to
     run.
- **Knowledge Base & Notes** -- AFFiNE and Trilium Notes both cover the same
  personal-notes/knowledge-base niche; no need for both.
  1. [Paperless-ngx](https://docs.paperless-ngx.com/) -- turns physical
     documents into a searchable archive, distinct and high-value.
  2. [Trilium Notes](https://triliumnotes.org/) -- mature, lightweight
     hierarchical notes app.
  3. [AFFiNE](https://affine.pro/) -- overlaps with Trilium above (notes +
     lightweight project management); heavier/newer project, rank below
     Trilium unless the project-management half is specifically wanted.
  4. [Readeck](https://readeck.org/en/) -- web clipper/bookmark manager,
     narrower niche than the above.
- **Organization & Workflow**
  1. [Baikal](https://sabre.io/baikal/) -- simple CalDAV/CardDAV sync, solves
     a concrete recurring need (calendar/contacts).
  2. [Kaneo](https://kaneo.app/) -- self-hosted project management; nice to
     have, not essential for personal use.
- **Travel & Navigation**
  1. [AdventureLog](https://adventurelog.app/) -- personal travel
     journal, direct fit.
  2. [OpenTripPlanner](https://www.opentripplanner.org/) -- heavier
     infrastructure (needs GTFS/OSM data feeds), niche unless trip-planning
     is a recurring itch.

### Smart Home & Automation

Complementary, not competing -- typically deployed together.

1. [Home Assistant](https://www.home-assistant.io/) -- central hub, deploy
   first.
2. [Frigate](https://docs.frigate.video/configuration/pwa/) -- NVR/object
   detection, only relevant once IP cameras are in play.
3. [Node-RED](https://nodered.org/) -- automation glue, most useful once
   Home Assistant already has entities to wire up.

### Home & Inventory

1. [Homebox](https://homebox.software/en/) -- general home inventory,
   broadest fit.
2. [Mealie](https://mealie.io/) -- recipe manager/meal planner.
3. [Binner](https://binner.io/) -- electronic parts inventory; niche unless
   doing serious electronics work.

### AI & Machine Learning

Dropped [nyno](https://github.com/empowerd-cms/nyno) -- niche, young project
(~300 GitHub stars as of Jan 2026), narrowly focused on YAML-defined
"EU-AI-compliant" AI workflows. Directly overlaps with n8n's niche but with a
tiny fraction of the maturity, integrations, and community.

Workflow-automation tools researched, ranked by fit for a single-admin,
GitOps-run homelab already running many self-hosted apps to wire together
(Home Assistant, Immich, Grafana alerts, Paperless-ngx, etc.):

1. [n8n](https://n8n.io) -- most mature option, by far the largest
   integration/community-node library, which matters most here: the value of
   a workflow tool in this setup is gluing together the *other* apps in this
   list. License is "fair-code" (Sustainable Use License) -- free for
   internal/personal self-hosting, only restricted for reselling n8n itself
   as a hosted service, which doesn't apply here.
2. [Activepieces](https://www.activepieces.com/) -- closest functional
   alternative to n8n, genuinely MIT-licensed (no fair-code caveat), 200+
   integrations, actively growing fast through 2025-2026. Worth a look if
   n8n's license terms ever actually matter, or its Zapier-like UI is
   preferred.
3. [Windmill](https://www.windmill.dev/) -- code-first (write real
   Python/TypeScript/Bash instead of wiring nodes), AGPLv3. Fits this user's
   existing IaC/scripting-heavy workflow better than a node canvas, at the
   cost of a smaller integrations library than n8n/Activepieces.
4. [Kestra](https://kestra.io/) -- Airflow-style data/infra orchestration
   (Apache 2.0, large and fast-growing community). Overkill for typical
   homelab automation (reminders, webhooks, notifications); only worth it if
   workflows grow into real scheduled data pipelines.
5. [Huginn](https://github.com/huginn/huginn) -- the original self-hosted
   automation tool (Ruby, agent-based), predates n8n by years. Smaller
   community and integration set than the above now; mainly of interest for
   its low resource footprint.

- [Ollama](https://ollama.com/) -- local LLM runtime; foundational, enables
  AI features in other self-hosted tools (including as an n8n/Activepieces/
  Windmill node for local-model workflow steps).
- [MangaTranslator](https://github.com/meangrinch/MangaTranslator) -- niche
  personal-use tool, unrelated to the automation tools above.

### Media

Dropped [PhotoPrism](https://www.photoprism.org/) -- directly redundant with
Immich below (same self-hosted photo-management niche); Immich is more
actively developed and has the stronger mobile/backup story.

1. [Immich](https://immich.app/) -- self-hosted photo and video gallery.

## Hardware to investigate

- coral tpu -- pairs with Frigate above (hardware-accelerates its object
  detection); only worth acquiring once/if Frigate is actually deployed.

## Resources

- <https://awesome-web.theravenhub.com/>
- <https://www.cncf.io/projects/>
