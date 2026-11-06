# Runbook: service without metrics

[Español](../es/servicio-sin-metricas.md) · **English**

> Practice exercise. Service and dashboard names come from the
> [sre-slo-lab](https://github.com/seamnex/sre-slo-lab) and from the fictional
> company in this repository's postmortems.

| | |
|---|---|
| **Alert** | `SLOSinDatos` (page) |
| **What it means** | Prometheus can't read the metrics of a service with an SLO. **While it lasts, that service's burn-rate alerts are blind**: the absence of alerts doesn't mean the service is fine. |
| **Urgency** | High. It may be a total outage, or the service may be working and we just can't see it. Both are handled now. |
| **Created from** | [INC-2026-031](../../postmortems/en/2026-08-27-blind-monitoring-otp.md) |

---

## First 5 minutes: down or blind?

The alert has two possible causes with very different consequences. The first
step is telling them apart.

1. **Does the service respond?** Test the user path, not the health check:

   ```bash
   curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://<service>/api/checkout
   ```

   - **No response, or 5xx** → **it's down.** Declare an incident and follow
     the [error budget burn](error-budget-burn.md) runbook: impact is total,
     even though no burn-rate alert says so.
   - **Responds fine** → **we're blind.** Continue with the diagnosis below.

2. **What does Prometheus say about the target?**

   ```bash
   curl -s localhost:9090/api/v1/targets \
     | jq '.data.activeTargets[] | select(.labels.job=="checkout") | {health, lastError, lastScrape}'
   ```

   | `lastError` | Likely cause |
   |---|---|
   | `context deadline exceeded` | Something blocks the connection: `NetworkPolicy`, firewall, security group |
   | `connection refused` | The metrics port isn't listening: the process changed port or doesn't expose `/metrics` |
   | `no such host` | DNS: the service changed name or namespace |
   | `server returned HTTP status 401/403` | Authentication was added to the metrics endpoint |
   | *(target missing)* | Service discovery changed: labels, annotations, `ServiceMonitor` |

## Diagnosis — if we're blind

1. **What changed?** Look for changes in the window since the target went
   `down` (`lastScrape` says when the last successful one was): network
   policies, service versions, Prometheus configuration.

2. **Test the scrape from where Prometheus does it**, not from your own
   machine:

   ```bash
   kubectl exec -n monitoring deploy/prometheus -- \
     wget -qO- -T 5 http://<pod-ip>:<port>/metrics | head
   ```

   If it fails from there and works from elsewhere, it's the network.

3. **Check the service namespace's `NetworkPolicy` objects:**

   ```bash
   kubectl get networkpolicy -n <namespace> -o yaml
   ```

   Is there an ingress rule allowing traffic from the `monitoring` namespace to
   the metrics port?

## Mitigation

1. **While blind, someone checks by hand.** Test the user path every 5 minutes
   and log the result in the incident channel. It isn't elegant, but it's the
   only replacement for the alert that isn't working.
2. **Restore the scrape** with the smallest change: add the ingress rule,
   revert the port change, fix the label. The long-term fix can wait for the
   postmortem; visibility can't.
3. If it can't be restored quickly: find an alternative signal (logs, load
   balancer metrics, client-side metrics) and create a temporary alert on it.

## Verification

- [ ] The target shows `up` in Prometheus.
- [ ] `SLOSinDatos` moves to `resolved`.
- [ ] The service's SLIs have values again:

  ```promql
  slo:sli_errores:ratio_rate5m
  ```

- [ ] **Review the blind period.** With metrics back, check whether there was
      impact while nothing was visible: logs, support tickets, dependency
      metrics. A period without data isn't a period without incidents; it's a
      period without evidence.

## Afterwards

- Postmortem if the blind period lasted more than 30 minutes, even with no
  impact: monitoring that can break without anyone noticing will break again.
- If a change caused it: add "verify monitoring targets are still `up`" to
  that type of change's checklist.
