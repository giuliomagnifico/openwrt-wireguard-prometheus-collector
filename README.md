
# OpenWrt WireGuard Prometheus collector

Prometheus collector for OpenWrt that exports WireGuard VPN peer statistics using `prometheus-node-exporter-lua`. It exposes per-peer traffic counters, latest handshake timestamps and connection metadata, with labels for interface, public key, endpoint, allowed IPs and peer name.

Peer names are resolved automatically from the OpenWrt UCI network configuration.

The collector runs directly on OpenWrt and does not require a separate WireGuard exporter service.

## Dashboard

WireGuard traffic monitoring in Grafana, showing transmitted and received traffic for each VPN peer over a customizable time range.

<img width="1374" height="408" alt="Safari 20-10-2026 at 06 47 08" src="https://github.com/user-attachments/assets/1c13da49-42b1-4fca-bec5-6f0fb26ac921" />

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

Both queries calculate the total traffic recorded for each WireGuard peer over the selected Grafana time range, including counter resets caused by WireGuard interface or router restarts.

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

With `Instant`, the query calculates the total only once, significantly reducing query execution time.

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

### Notes

WireGuard traffic counters reset when a peer or interface is recreated. Unlike queries that read the current counter directly, `increase()` accounts for counter resets detected within the selected time range.

Historical data must still be available in Prometheus or Mimir. Traffic that was never scraped or has been deleted by the retention policy cannot be recovered.

The selected time range is a rolling window, not a permanent all-time total. For example, `365d` always represents the previous 365 days.

Changes to a peer's endpoint can also create new Prometheus time series. This may affect historical calculations when counter continuity across those series cannot be established.

---

