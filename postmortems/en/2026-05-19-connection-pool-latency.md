# Postmortem: slow balance queries for 58 minutes after a deploy

[Español](../es/2026-05-19-latencia-pool-de-conexiones.md) · **English**

> **Simulated incident.** Pagoya and everything described in this document are
> fictional: this is a postmortem-writing exercise, not a real incident.
> See the [repository notice](../../README.en.md#notice).

| | |
|---|---|
| **ID** | INC-2026-019 |
| **Severity** | P2 |
| **Status** | Closed |
| **Incident date** | 2026-05-19 (Tuesday) |
| **Impact duration** | 58 min (10:40 → 11:38) |
| **Time to detect (MTTD)** | 12 min |
| **Time to mitigate** | 46 min |
| **Affected services** | `api-cuentas` (balance and transactions) |
| **Incident Manager** | On-call Incident Manager |
| **Document authors** | Incident Manager, Accounts Tech Lead |
| **Reviewed by** | Accounts team, SRE — 2026-05-22 |

## 1. Executive summary

Between 10:40 and 11:38 on Tuesday, May 19, balance and transaction queries in
the app took 2 to 5 seconds instead of the usual 150 ms, and 1.8% of queries
ended in a timeout error. No money was lost or moved incorrectly. The cause was
a change deployed at 10:40 that held a database connection while waiting for
the anti-fraud service to respond. With mid-morning traffic, connections ran
out. It was resolved with a rollback. To prevent a repeat we will deploy to a
fraction of the traffic first, with an automated gate on latency.

## 2. Impact

| Dimension | Value | Source |
|---|---|---|
| Affected users | ~41,000 with at least one slow query | Unique users in the incident window |
| Slow queries (> 300 ms) | 612,000 of 694,000 (88%) | `api-cuentas` `http_request_duration_seconds` histogram |
| Failed queries (app timeout at 5 s) | 12,500 (1.8%) | `http_requests_total{code="504"}` |
| Error budget consumed — **latency SLO** (99% < 300 ms) | **41%** of the monthly budget | Recording rule `slo:sli_errores:ratio_rate30d` |
| Error budget consumed — availability SLO (99.5%) | 1.7% of the monthly budget | Same |
| Financial impact | No direct loss: read-only | — |
| Support contacts | 214 | Ticketing system, "balance" category |

## 3. Timeline

All times in UTC-3.

| Time | Event |
|---|---|
| 10:34 | Deploy of `api-cuentas` v4.18 starts (rolling update, 6 pods in 6 minutes). It includes the new "recent transactions with risk score" section and a migration that adds a column. |
| 10:40 | **Impact starts.** Rollout completes. `api-cuentas` p99 goes from 180 ms to 2.4 s. |
| 10:52 | **Detection.** `SLOQuemaRapida` fires for the latency SLO (burn rate 18×). The on-call SRE is paged. |
| 10:55 | The on-call SRE sees the correlation with the deploy on the dashboard (deploy annotation at 10:34). |
| 10:58 | **P2 incident declared.** War Room with SRE, Incident Manager and Accounts Tech Lead. |
| 11:02 | First hypothesis: the migration locked the table. The database is checked: CPU at 35%, no long locks, no slow queries. Ruled out. |
| 11:09 | The Tech Lead checks the resource saturation panel: **the connection pool is at 100% on all 6 pods** (20 of 20) with 340 requests waiting for a connection. |
| 11:11 | A rollback is proposed. It stalls: the release included a migration and **nobody in the War Room can confirm whether v4.17 works with the new column.** |
| 11:24 | The migration's author confirms it is additive (new nullable column, no default) and that v4.17 ignores it. |
| 11:31 | **Mitigation.** Rollback to v4.17. |
| 11:38 | **Full recovery.** Connection pool at 30%, p99 at 170 ms. |
| 11:50 | War Room closed. |
| 14:20 | The cause is confirmed with a profiler in staging: each transactions query holds its connection for ~800 ms, the time the anti-fraud service takes. |

## 4. Root cause

### 5 whys

1. **Why did queries take seconds?** Because they were waiting for a free
   database connection: the pool was at 100% on all six pods.
2. **Why did the pool run out?** Because the new endpoint opened a transaction,
   read the transactions and, **inside the same transaction**, synchronously
   called the anti-fraud service (p50 of 600 ms). The connection was held the
   whole time, 40 times longer than before.
3. **Why didn't tests or code review catch it?** Because in the load testing
   environment the anti-fraud service is a mock that responds in 5 ms: the
   pattern was invisible at that latency. In code review, the transaction scope
   wasn't visible: it's defined by an annotation in another file.
4. **Why did it reach 100% of traffic before anything stopped it?** Because the
   deploy is a rolling update that covers all traffic in 6 minutes, with no
   canary stage and no automated gate on latency.
5. **Why was the first signal the SLO alert and not pool saturation?** Because
   pool metrics were exported but had no alert. Pool saturation is a leading
   indicator: it hit 100% at 10:38 and the SLO alert fired 14 minutes later.

**Root cause:** a code change held database connections during a slow external
call. The test environment didn't reproduce the real latency of that
dependency, and the deploy process had no stage that exposed the change to a
fraction of traffic before taking it to 100%.

### Contributing factors

- **The migration's reversibility wasn't documented.** It cost 20 minutes of
  impact to confirm something the author knew from the start.
- **The anti-fraud call had no timeout of its own**: it used the HTTP client's
  default of 30 seconds.
- **The saturation panel existed, but not on the main dashboard.** It was found
  17 minutes into the War Room.

## 5. What went well

- **The SLO alert detected the problem before users did.** The first support
  tickets arrived at 11:05, 13 minutes after the page.
- The deploy annotation on the dashboard made the correlation obvious in 3
  minutes.
- The migration hypothesis was ruled out with evidence (CPU, locks, slow
  queries) in 7 minutes, instead of being acted on.
- Once decided, the rollback took 7 minutes and worked the first time.

## 6. What went wrong

- **20 minutes of avoidable impact** waiting to confirm the rollback was safe.
- **The saturation signal was available and wasn't checked first.** We started
  with the database —the usual suspect— and not with the resource that was
  running out.
- **The change went to 100% of traffic at once.** With a 10% canary, the impact
  would have been a tenth and the rollback automatic.

## 7. Where we got lucky

- **The migration was additive.** Had it renamed or dropped a column, rollback
  would have been impossible without a second migration, and the impact would
  have lasted as long as writing and testing it took.
- **It wasn't payday.** Balance query traffic on the 1st and 15th of each month
  is about 3 times that of an ordinary Tuesday. At that volume, the pool would
  have run out in the first minute and timeouts would have been the majority,
  not 1.8%.

## 8. Action items

| # | Action | Type | Owner | Due | Status |
|---|---|---|---|---|---|
| 1 | 10% canary stage for 15 minutes, with automatic rollback if the latency SLO burn rate exceeds 6× | Mitigate | Platform | 2026-06-30 | In progress |
| 2 | Connection pool saturation alert: above 80% for 5 minutes | Detect | SRE | 2026-05-29 | Closed |
| 3 | Saturation panel (pool, threads, CPU) on every service's main dashboard | Detect | SRE | 2026-05-29 | Closed |
| 4 | The anti-fraud mock used in load tests reproduces the production latency distribution | Prevent | QA + Accounts | 2026-06-15 | Open |
| 5 | Code review rule and static check: no network calls inside a database transaction | Prevent | Accounts | 2026-06-15 | In progress |
| 6 | The PR template requires stating whether the migration is reversible and whether the previous version is compatible | Mitigate | Architecture | 2026-05-29 | Closed |
| 7 | 300 ms timeout and circuit breaker on the anti-fraud call, degrading to "score unavailable" | Mitigate | Accounts | 2026-06-15 | Open |

## 9. Lessons learned

- **For a latency problem, first look at which resource is saturating**, not at
  which component usually fails. The database was the usual suspect and was
  healthy; the pool, which nobody was watching, was at 100%.
- **A mock that's faster than the real dependency hides exactly this class of
  bug.** Load tests measure what the test environment lets them see.
- **"Can we roll back?" is answered before the deploy, not in the War Room.**

## Appendix

- Runbook used: [error budget burn](../../runbooks/en/error-budget-burn.md), "Latency" section
- Query that showed the saturation:

  ```promql
  max by (pod) (db_pool_connections_in_use{service="api-cuentas"})
    / max by (pod) (db_pool_connections_max{service="api-cuentas"})
  ```
