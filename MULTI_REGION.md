# Super JinX — Multi-Region Railway setup

This version changes the topology from **one all-in-one service** to:

- 1 central Panel service + its persistent Volume
- 4 independent PasarGuard Node services
- 1 node per Railway region
- One subscription can contain every region
- The subscription page has region filters so the customer can copy/QR a config for one region

Railway currently documents four deploy regions: US West, US East, EU West (Amsterdam), and Southeast Asia (Singapore). Volumes cannot be used with replicas, so the Panel stays a single persistent service while the stateless regional nodes are separate services. Railway private networking gives each service a `*.railway.internal` hostname.

## 1. Create the central Panel

Use the repository root and the normal `Dockerfile`.

1. Create a Railway project.
2. Add the repo as a service.
3. Keep the service in one region (EU West is a sensible central location).
4. Attach a Volume at `/var/lib/pasarguard`.
5. Generate a public domain targeting port `8080`.

Do **not** enable replicas on this service because it has a Volume. Railway explicitly says replicas cannot be used with Volumes. citeturn0search3

## 2. Create four regional Node services

Create four additional services in the **same Railway project and production environment**.

Use the same Git repository but set the Dockerfile path to `Dockerfile.node`.

Recommended names/regions:

| Service | Railway region |
|---|---|
| `jinx-nl` | EU West / Amsterdam |
| `jinx-us-east` | US East / Virginia |
| `jinx-us-west` | US West / California |
| `jinx-sg` | Southeast Asia / Singapore |

Generate a public domain for every node. The domain must target the node's HTTP port `8080` because the end-user Xray traffic is WebSocket/HTTP based. Railway-provided domains are created from **Settings → Networking → Generate Domain**.

The Node control API listens on port `62050` internally and should remain private. The Panel talks to it using the service's private hostname, e.g. `jinx-nl.railway.internal:62050`. Railway documents private service DNS in the form `<service-name>.railway.internal`. citeturn3search1

## 3. Node variables

On every node service add:

```text
JINX_NODE_SECRET=<same long random secret on all 5 services>
JINX_NODE_REGION=nl
JINX_PANEL_DOMAIN=<your central panel public domain>
```

Use `us-east`, `us-west`, and `sg` for the other three nodes.

The Node derives its API key from the shared secret + region, so you do not have to manually copy four API keys.

## 4. Central Panel variables

On the central Panel add:

```text
JINX_NODE_SECRET=<same long random secret>
JINX_REGIONS_JSON=<the JSON from multi-region.env.example with your real public domains>
```

Example:

```json
[
  {"id":"nl","name":"🇳🇱 Netherlands","node_name":"JinX-NL","address":"jinx-nl.railway.internal","port":62050,"public_domain":"xxxx-nl.up.railway.app"},
  {"id":"us-east","name":"🇺🇸 USA East","node_name":"JinX-US-East","address":"jinx-us-east.railway.internal","port":62050,"public_domain":"xxxx-useast.up.railway.app"},
  {"id":"us-west","name":"🇺🇸 USA West","node_name":"JinX-US-West","address":"jinx-us-west.railway.internal","port":62050,"public_domain":"xxxx-uswest.up.railway.app"},
  {"id":"sg","name":"🇸🇬 Singapore","node_name":"JinX-SG","address":"jinx-sg.railway.internal","port":62050,"public_domain":"xxxx-sg.up.railway.app"}
]
```

The Panel automatically fetches each Node's public CA from `/ca.pem`, then registers the Node through the private network. The CA is public certificate material; the Node API key is not exposed.

## 5. Shared transport paths

The Panel creates `/jinx-paths.json` from its persistent path file. Regional Nodes fetch it automatically. You normally do **not** need to set `JINX_SHARED_PATHS_JSON` manually.

## 6. First deployment order

Deploy in this order:

1. Central Panel
2. Generate its public domain
3. Create the four Node services and generate their domains
4. Add Node variables
5. Add the Panel variables
6. Redeploy the Panel
7. Watch Panel logs for `multi-region node ready`

When all four nodes are connected, the Panel will create region-specific cores, hosts and groups automatically.

## 7. What the customer sees

The generated subscription contains configs from all regions. The custom subscription page adds buttons such as:

- `همه لوکیشن‌ها`
- `🇳🇱 Netherlands`
- `🇺🇸 USA East`
- `🇺🇸 USA West`
- `🇸🇬 Singapore`

The customer can filter the list, then copy or scan the config for the desired region. The subscription itself remains one link, so the customer can switch regions without buying another subscription.

## 8. Important Railway detail

Do not use Railway's multi-region replica feature for the central Panel. Railway routes multi-region replicas behind one public domain, but replicas cannot use a Volume. The architecture here intentionally uses **separate stateless Node services** and **one persistent Panel** instead. citeturn0search4turn0search3
