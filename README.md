# OpenWrt WireGuard Prometheus collector

Prometheus collector for OpenWrt that exports WireGuard VPN peer statistics using `prometheus-node-exporter-lua`. It exposes per-peer traffic counters, latest handshake timestamps and connection metadata, with labels for interface, public key, endpoint, allowed IPs and peer name.

Peer names are resolved automatically from the OpenWrt UCI network configuration.

The collector runs directly on OpenWrt and does not require a separate WireGuard exporter service.

## Dashboard

WireGuard traffic monitoring in Grafana, showing transmitted and received traffic for each VPN peer over a customizable time range.

<img width="1374" height="408" alt="WireGuard traffic monitoring dashboard" src="https://github.com/user-attachments/assets/1c13da49-42b1-4fca-bec5-6f0fb26ac921" />

### Total WireGuard Transmitted

```promql
sum by (allowed_ips) (
  increase(wireguard_sent_bytes_total[$__range])
)
```

### Total WireGuard Received

```promql
sum by (allowed_ips) (
  increase(wireguard_received_bytes_total[$__range])
)
```

Both queries calculate the traffic recorded for each WireGuard peer over the selected Grafana time range, accounting for detected counter resets caused by WireGuard interface or router restarts.

The calculations use historical data retained by Prometheus or Mimir.

### Grafana query options

To customize the time range for these panels, expand **Query options** in the Grafana panel editor.

Recommended settings:

- **Relative time:** Set your preferred time range, such as `1h`, `24h`, `7d`, `30d` or `365d`.
- **Time shift:** Leave empty.
- **Query type:** Select `Instant` instead of `Range` in each Prometheus query's Options.

The `$__range` variable automatically follows the selected dashboard time range or the panel's **Relative time** override.

For example:

```text
Relative time: 1h    → Last hour
Relative time: 24h   → Last 24 hours
Relative time: 7d    → Last 7 days
Relative time: 30d   → Last 30 days
Relative time: 365d  → Last 365 days
```

**Important:** Use `Instant` queries for these Pie chart panels. A `Range` query with `increase()` over a long period, such as 365 days, can be extremely expensive because Prometheus or Mimir repeatedly evaluates overlapping historical windows.

With `Instant`, the query calculates the total only once, significantly reducing query execution time. Very long intervals can still require substantial processing.

### Recommended Grafana visualization

- Visualization: Pie chart
- Pie chart type: Donut
- Unit: bytes (SI)
- Legend: Table
- Legend values: Value and Percent
- Legend placement: Right
- Query type: Instant

The `allowed_ips` label identifies each VPN peer by its configured tunnel IP address. You can configure Grafana display-name mappings to show friendly device names such as iPhone, iPad Pro or MacBook Air.

Alternatively, use `sum by (name)` to group traffic by peer names resolved from OpenWrt UCI.

### Traffic history and counter resets

WireGuard traffic counters reset when a peer or interface is recreated. Unlike queries that read the current counter directly, `increase()` accounts for counter resets detected within the selected time range.

Historical data must still be available in Prometheus or Mimir. Traffic that was never scraped or has been deleted by the retention policy cannot be recovered.

The selected time range is a rolling window, not a permanent all-time total. For example, `365d` always represents the previous 365 days.

Changes to a peer's endpoint can also create new Prometheus time series. This may affect historical calculations when counter continuity across those series cannot be established.

## Metrics

The collector exports:

```text
wireguard_latest_handshake_seconds
wireguard_received_bytes_total
wireguard_sent_bytes_total
```

| Metric | Type | Description |
|---|---|---|
| `wireguard_latest_handshake_seconds` | Gauge | Unix timestamp of the latest successful handshake |
| `wireguard_received_bytes_total` | Counter | Total bytes received from the peer |
| `wireguard_sent_bytes_total` | Counter | Total bytes sent to the peer |

Traffic directions are from the OpenWrt router's perspective:

- **Received:** traffic from the WireGuard peer to the router
- **Sent:** traffic from the router to the WireGuard peer

The byte counters represent cumulative traffic since the corresponding WireGuard peer state was initialized or reset.

### Labels

```text
interface
public_key
endpoint
allowed_ips
name
```

| Label | Description |
|---|---|
| `interface` | WireGuard interface, such as `wg0` |
| `public_key` | Public key identifying the WireGuard peer |
| `endpoint` | Current remote IP address and port |
| `allowed_ips` | Allowed IP addresses configured for the peer |
| `name` | Peer section name resolved from OpenWrt UCI |

Peer names are obtained from:

```sh
uci show network
```

The collector matches each WireGuard peer's public key against the `public_key` entries in the OpenWrt network configuration.

For example, a UCI peer section named `iphone` will be exported with the label:

```text
name="iphone"
```

If no matching UCI entry exists, the collector uses `name="unknown"`.

Anonymous UCI peer sections may appear with their generated section identifiers rather than a descriptive device name.

## Installation

### Requirements

- OpenWrt with WireGuard configured
- `prometheus-node-exporter-lua`
- `wireguard-tools` providing the `wg` command
- Access to the OpenWrt UCI network configuration

The collector uses standard Lua functionality and the existing Prometheus Lua exporter. No additional Lua libraries or separate daemon are required beyond the exporter dependencies.

### Install dependencies

On OpenWrt 25.12 or newer:

```sh
apk -U add prometheus-node-exporter-lua wireguard-tools
```

On OpenWrt 24.10 or older:

```sh
opkg update && opkg install prometheus-node-exporter-lua wireguard-tools
```

Skip this step if the packages are already installed.

### Install the collector

Copy the collector to the Prometheus Lua collectors directory.

From your OpenWrt device:

```sh
mkdir -p /usr/lib/lua/prometheus-collectors && wget -O /usr/lib/lua/prometheus-collectors/wireguard.lua https://raw.githubusercontent.com/giuliomagnifico/openwrt-wireguard-prometheus-collector/main/wireguard.lua && chmod 644 /usr/lib/lua/prometheus-collectors/wireguard.lua && /etc/init.d/prometheus-node-exporter-lua restart
```

The Lua file is loaded as a module by `prometheus-node-exporter-lua`, so executable permissions are not required.

### Test the collector

From your OpenWrt device:

```sh
wget -qO- 'http://127.0.0.1:9100/metrics?collect[]=wireguard' | grep wireguard | head
```

You should see output similar to:

```text
root@R5S:~# wget -qO- 'http://127.0.0.1:9100/metrics?collect[]=wireguard' | grep wireguard | head
# TYPE wireguard_latest_handshake_seconds gauge
wireguard_latest_handshake_seconds{endpoint="192.168.1.105:51820",public_key="xyz=",name="@wireguard_wg0[0]",allowed_ips="10.4.0.2/32",interface="wg0"} 1792434193
# TYPE wireguard_received_bytes_total counter
wireguard_received_bytes_total{endpoint="192.168.1.105:51820",public_key="xyz=",name="@wireguard_wg0[0]",allowed_ips="10.4.0.2/32",interface="wg0"} 7084344
# TYPE wireguard_sent_bytes_total counter
wireguard_sent_bytes_total{endpoint="192.168.1.105:51820",public_key="xyz=",name="@wireguard_wg0[0]",allowed_ips="10.4.0.2/32",interface="wg0"} 37757436
# TYPE wireguard_latest_handshake_seconds gauge
wireguard_latest_handshake_seconds{endpoint="(none)",public_key="xyz",name="@wireguard_wg0[1]",allowed_ips="10.4.0.4/32",interface="wg0"} 0
# TYPE wireguard_received_bytes_total counter
wireguard_received_bytes_total{endpoint="(none)",public_key="xyz",name="@wireguard_wg0[1]",allowed_ips="10.4.0.4/32",interface="wg0"} 0
```


## Prometheus configuration

The default OpenWrt exporter configuration listens on the loopback interface.

To allow a Prometheus server on your trusted LAN to scrape the endpoint, configure the exporter to listen on the LAN interface:

```sh
uci set prometheus-node-exporter-lua.main.listen_interface='lan' && uci commit prometheus-node-exporter-lua && /etc/init.d/prometheus-node-exporter-lua restart
```

Ensure that the router firewall permits access from your Prometheus server.

Add the following job to `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'openwrt-wireguard'
    scrape_interval: 30s
    metrics_path: /metrics
    params:
      'collect[]': ['wireguard']
    static_configs:
      - targets:
          - '192.168.1.1:9100'
```

Replace `192.168.1.1` with your OpenWrt router's LAN IP address.

The `collect[]` parameter ensures that this job requests only the WireGuard collector.

Alternatively, if you already scrape all collectors from the same OpenWrt exporter, no additional Prometheus job is required. The WireGuard metrics will be included automatically.

Do not expose the metrics endpoint to the public Internet. It does not provide built-in authentication and can reveal VPN peer metadata.

## Example PromQL queries

For time-based panels, use Grafana's query options.

Recommended Grafana query options:

```text
Query options → Relative time: 1h / 24h / 7d / 30d / 365d
```

Use `$__range` inside `increase()` so the queries automatically follow the selected dashboard time range or panel relative time.

For cumulative traffic Pie charts, select `Instant` as the Prometheus query type.

### Total cumulative traffic by peer

Shows the current total traffic recorded by WireGuard for each peer since its counters were initialized or reset.

```promql
sum by (name, interface) (
  wireguard_received_bytes_total
  +
  wireguard_sent_bytes_total
)
```

This query uses the current WireGuard counters and does not preserve previous counter values after a reset.

### Total traffic by peer over the selected Grafana time range

Useful for panels displaying the last hour, last 24 hours, last 7 days or last 30 days.

```promql
topk(20, sum by (name, interface) (
  increase(wireguard_received_bytes_total[$__range])
  +
  increase(wireguard_sent_bytes_total[$__range])
))
```

### Received traffic by peer over the selected Grafana time range

Traffic received by the OpenWrt router from each WireGuard peer.

```promql
topk(20, sum by (name, interface) (
  increase(wireguard_received_bytes_total[$__range])
))
```

### Sent traffic by peer over the selected Grafana time range

Traffic sent by the OpenWrt router to each WireGuard peer.

```promql
topk(20, sum by (name, interface) (
  increase(wireguard_sent_bytes_total[$__range])
))
```

### Real-time received traffic rate by peer

```promql
sum by (name, interface) (
  rate(wireguard_received_bytes_total[$__rate_interval])
) * 8
```

### Real-time sent traffic rate by peer

```promql
sum by (name, interface) (
  rate(wireguard_sent_bytes_total[$__rate_interval])
) * 8
```

### Total real-time traffic rate by peer

```promql
sum by (name, interface) (
  rate(wireguard_received_bytes_total[$__rate_interval])
  +
  rate(wireguard_sent_bytes_total[$__rate_interval])
) * 8
```

Multiplying by 8 converts bytes per second into bits per second.

### Time since the latest handshake

Shows the elapsed seconds since each peer's last successful WireGuard handshake.

```promql
time() - (wireguard_latest_handshake_seconds > 0)
```

The comparison filters out peers that have never completed a handshake.

### Peers with a handshake in the last 3 minutes

```promql
(time() - (wireguard_latest_handshake_seconds > 0)) < bool 180
```

The result is:

- `1` — the last handshake occurred within 180 seconds
- `0` — the last handshake is older than 180 seconds

Peers that have never completed a handshake are omitted.

**Important:** This is a recent-handshake indicator, not a definitive VPN connection-status metric. WireGuard is connectionless, and an inactive peer may remain reachable even without a recent handshake.

## Grafana units

For cumulative traffic and `increase()` queries:

```text
bytes (SI)
```

For traffic-rate queries multiplied by 8:

```text
bits/sec
```

For elapsed handshake time:

```text
seconds (s)
```

Recommended panel types for total traffic:

- Pie chart
- Bar gauge
- Table
- Stat

Recommended panel types for real-time traffic rates:

- Time series
- Bar gauge

Recommended panel types for handshake monitoring:

- Stat
- Table
- Time series

Use the `name` label for more readable Grafana legends, for example:

```text
{{name}}
```

## Notes

### Handshake timestamps

`wireguard_latest_handshake_seconds` contains a Unix timestamp, not the number of elapsed seconds.

A value of `0` means that the peer has not completed a successful handshake since its current state was initialized.

Use `time()` in PromQL to calculate how long ago the handshake occurred.

### Traffic counters

WireGuard transfer counters are cumulative and may reset when a peer or interface is recreated.

Use `rate()` for traffic rates and `increase()` for traffic over a selected time range.

`$__range` follows the dashboard time range or the panel's `Relative time` option:

```text
Relative time: 1h    → $__range = 1h
Relative time: 24h   → $__range = 24h
Relative time: 7d    → $__range = 7d
Relative time: 30d   → $__range = 30d
Relative time: 365d  → $__range = 365d
```

`Time shift` should usually be left empty unless you explicitly want to compare with a previous period.

For long historical periods, use `Instant` queries for Stat, Pie chart and other panels that display a single aggregated value.

### Changing endpoints

The `endpoint` label contains the current remote address and port.

When a WireGuard peer changes network, for example when moving from Wi-Fi to a mobile network, its endpoint may change.

Prometheus then treats the new label combination as a different time series, even though the WireGuard peer is unchanged.

For long-term traffic aggregation, prefer the `name`, `interface`, `allowed_ips` or `public_key` labels rather than grouping by endpoint.

Grouping by a stable label does not completely eliminate discontinuities caused by changing endpoints, because `increase()` still operates on the individual underlying series before aggregation.

### Security and privacy

The collector reads `wg show all dump`, but never exports private keys or preshared keys.

However, these labels can reveal information about the VPN configuration:

```text
public_key
endpoint
allowed_ips
name
```

Restrict access to the exporter to trusted monitoring hosts.

Avoid sharing raw metric output publicly without removing sensitive peer metadata.

### Firmware upgrades

The collector is installed manually under:

```text
/usr/lib/lua/prometheus-collectors/wireguard.lua
```

Custom files in this directory may not survive OpenWrt firmware upgrades.

After upgrading, reinstall the collector using the installation command above.

Alternatively, add the file to the OpenWrt sysupgrade backup configuration:

```sh
grep -qxF '/usr/lib/lua/prometheus-collectors/wireguard.lua' /etc/sysupgrade.conf || echo '/usr/lib/lua/prometheus-collectors/wireguard.lua' >> /etc/sysupgrade.conf
```

This requests that sysupgrade preserve the file when configuration backups are retained.

### Troubleshooting

Check that the WireGuard interfaces and peers are available:

```sh
wg show
```

Check the Lua collector syntax:

```sh
luac -p /usr/lib/lua/prometheus-collectors/wireguard.lua
```

Check the exporter service:

```sh
/etc/init.d/prometheus-node-exporter-lua status
```

Verify that the collector returns metrics:

```sh
wget -qO- 'http://127.0.0.1:9100/metrics?collect[]=wireguard' | grep wireguard
```

If the collector is missing after a firmware upgrade, download it again and restart the service.

## References

- [OpenWrt Prometheus Lua exporter](https://github.com/openwrt/packages/tree/master/utils/prometheus-node-exporter-lua)
- [WireGuard tools and `wg` manual](https://github.com/WireGuard/wireguard-tools)
- [Prometheus query functions](https://prometheus.io/docs/prometheus/latest/querying/functions/)
- [Grafana Prometheus query editor](https://grafana.com/docs/grafana/latest/datasources/prometheus/query-editor/)
- [OpenWrt package management](https://openwrt.org/docs/guide-user/additional-software/managing_packages)
