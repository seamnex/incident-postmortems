# Runbook: error budget burn

[Español](../es/quema-de-error-budget.md) · **English**

> Practice exercise. Service and dashboard names come from the
> [sre-slo-lab](https://github.com/seamnex/sre-slo-lab) and from the fictional
> company in this repository's postmortems.

| | |
|---|---|
| **Alerts** | `SLOQuemaRapida` (page) · `SLOQuemaLenta` (ticket) |
| **What it means** | An SLO is consuming its error budget faster than is sustainable. The `slo` label says which one: `disponibilidad` (availability) or `latencia` (latency). |
| **Urgency** | **Page:** the budget runs out in days. Act now. **Ticket:** it runs out in weeks. Fix during business hours. |
| **Dashboard** | Grafana → *SLOs — Checkout* |
| **Used in** | [INC-2026-019](../../postmortems/en/2026-05-19-connection-pool-latency.md) |

---

## First 5 minutes

The goal of these 5 minutes **is not to find the cause**: it is to size the
impact and decide whether to declare an incident.

1. **Confirm it's real.** On the dashboard, check the 5-minute burn rate of the
   alert's SLO. If it's already below 1×, the problem ended on its own: go to
   [Afterwards](#afterwards) and don't declare anything.

2. **Size it.** What fraction of requests is failing or slow?

   ```promql
   slo:sli_errores:ratio_rate5m
   ```

3. **Look for a recent change.** It's the most frequent cause and the fastest
   to revert.
   - Deploys in the last 2 hours (dashboard annotations, CD pipeline history).
   - Configuration changes, feature flags, migrations.
   - Infrastructure changes: network, certificates, secrets.

4. **Decide.** If it's a page alert and the impact is ongoing, **declare the
   incident** and open the War Room. Better to declare and close after 10
   minutes than not declare and find out 40 minutes later it was a P1.

## Diagnosis

### If `slo="disponibilidad"` — 5xx errors

1. Which codes? All endpoints or just one?

   ```promql
   sum by (code) (rate(http_requests_total{job="checkout"}[5m]))
   ```

2. Is it the service or a dependency? Look for the most frequent errors in the
   last 15 minutes of logs. A connection or TLS error towards a dependency
   points outward; an exception of our own points at the code.

3. If it points to an external dependency: check its status page **and, in
   parallel**, verify our own side of the connection (credentials,
   certificates, DNS). See [TLS certificate expiring or expired](tls-certificate-expiring.md).

### If `slo="latencia"` — requests over 300 ms

For a latency problem, **first look at which resource is saturating**, not at
which component usually fails.

1. Saturation, in this order: database connection pool, threads or workers,
   CPU, memory.

   ```promql
   max by (pod) (db_pool_connections_in_use / db_pool_connections_max)
   ```

2. Dependency latency: did any external call become slow? A service that waits
   on another inherits its latency.

3. Did traffic change? A volume spike on a healthy system also saturates
   resources.

   ```promql
   sum(rate(http_requests_total{job="checkout"}[5m]))
   ```

## Mitigation

In this order of preference. **Mitigate first, understand later**: the root
cause is investigated with the impact already contained.

| If... | Do | Check first |
|---|---|---|
| There's a correlated deploy or change | **Rollback** | Did the change include a migration? Is it compatible with the previous version? If nobody knows, ask the author *now*, in parallel |
| The change is behind a feature flag | Turn the flag off | — |
| Saturation from volume | Scale out | That the bottleneck isn't shared (a database doesn't scale with more pods: adding pods can make it worse) |
| A dependency with an alternative is failing | Fail over to the alternative | That the alternative has capacity |
| A dependency without an alternative is failing | Degrade: disable the feature that depends on it | Communicate what stops working |

## Verification

The incident is mitigated when:

- [ ] The 5-minute burn rate is below 1×.
- [ ] The alert moves to `resolved` (with the 5-minute short window, it takes a few minutes).
- [ ] Traffic is back to its normal volume: a healthy SLI with half the traffic
      can mean users gave up trying.

## Escalation

| After | Without mitigation | Escalate to |
|---|---|---|
| 15 min | No hypothesis | Service Tech Lead |
| 30 min | No mitigation | Incident Manager decides whether to raise severity |
| At any time | The cause is another team's dependency | That team's on-call, with the dashboard and the evidence |

## Communication

- **Status page:** first update 15 minutes after declaring, even with no cause
  yet: what works, what doesn't, and when the next update will be.
- **Updates:** every 30 minutes while impact lasts.

## Afterwards

- Record how much error budget was consumed:

  ```promql
  1 - slo:error_budget_restante:ratio
  ```

- Postmortem required if the incident consumed more than 10% of the monthly
  budget or was declared P1. Use the [template](../../plantilla/postmortem.en.md).
- If the alert was a `SLOQuemaLenta` without an incident: open a ticket with
  the observed burn rate and the likely cause. It's debt to pay before it turns
  into a page.
