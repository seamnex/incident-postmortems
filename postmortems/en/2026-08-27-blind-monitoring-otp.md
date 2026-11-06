# Postmortem: OTP codes undelivered for 80 minutes, without a single alert

[Español](../es/2026-08-27-monitoreo-ciego-otp.md) · **English**

> **Simulated incident.** Pagoya and everything described in this document are
> fictional: this is a postmortem-writing exercise, not a real incident.
> See the [repository notice](../../README.en.md#notice).

| | |
|---|---|
| **ID** | INC-2026-031 |
| **Severity** | P2 |
| **Status** | Closed |
| **Incident date** | 2026-08-27 (Thursday) |
| **Impact duration** | 1 h 20 min (16:20 → 17:40) |
| **Time to detect (MTTD)** | **42 min**, from user complaints, not from an alert |
| **Time to mitigate** | 38 min |
| **Unmonitored period** | **4 h 10 min** (14:05 → 18:15) |
| **Affected services** | `otp-sms` (verification codes for sign-in) |
| **Incident Manager** | On-call Incident Manager |
| **Document authors** | Incident Manager, on-call SRE |
| **Reviewed by** | SRE, Security, Identity — 2026-09-01 |

## 1. Executive summary

Between 16:20 and 17:40 on Thursday, August 27, **35% of SMS verification
codes never reached users**, and about 1,850 could not sign in on the first
attempt. The SMS provider started throttling our messages when a marketing
campaign doubled the volume. But the main problem in this incident isn't that
failure: it's that **no alert detected it**. Two hours earlier, a network
security change had cut the monitoring system's access to the service, and
missing metrics don't fire any alert. We found out 42 minutes later, from
complaints. The main action items make the absence of data an alert in itself.

## 2. Impact

| Dimension | Value | Source |
|---|---|---|
| OTP codes requested | 6,400 | `otp-sms` logs (logs did arrive: they take a different path) |
| Codes not delivered | 2,240 (35%) | Provider delivery report |
| Users unable to sign in on the first attempt | ~1,850 | Unique users with an undelivered OTP |
| Error budget consumed — OTP delivery SLO (99% within 30 s) | **13%** of the monthly budget | 2,240 / 17,280 allowed in 30 days |
| Support contacts | 386 | Ticketing system, "code not arriving" category |
| Financial impact | No direct loss; campaign cost with reduced conversion | Marketing |

## 3. Timeline

All times in UTC-3.

| Time | Event |
|---|---|
| 14:05 | A *default-deny* `NetworkPolicy` is applied to the `otp` namespace as part of Security's hardening plan. The policy allows application traffic, **but not Prometheus** from the `monitoring` namespace. |
| 14:06 | The post-change check passes: the service responds to functional requests. **Prometheus stops scraping `otp-sms`.** No alert: there is no data to evaluate. |
| 14:06 → 18:15 | The `otp-sms` panels in Grafana go blank. Nobody is looking at them. |
| 16:15 | A marketing campaign with mandatory sign-in starts. OTP volume goes from ~40 to ~80 per minute. |
| 16:20 | **Impact starts.** The SMS provider starts throttling messages above the contracted throughput (~52 per minute). 35% of codes are not delivered. |
| 16:20 → 17:02 | The OTP SLO burn-rate alerts **don't fire**: without metrics, the SLI is "no data" and the condition is never met. |
| 16:48 | Support notices a rise in "code not arriving" tickets. It is treated as a mobile carrier problem, the usual cause. |
| 17:02 | **Detection.** Support escalates to the on-call SRE: 140 tickets in 40 minutes, across all carriers. |
| 17:05 | The on-call SRE opens the OTP dashboard: **panels empty since 14:06.** |
| 17:08 | **P2 incident declared.** War Room with SRE, Incident Manager and Identity. |
| 17:14 | `otp-sms` logs show `429 Too Many Requests` responses from the provider since 16:20. |
| 17:20 | The campaign is identified as the source of the volume increase. |
| 17:31 | **Mitigation.** Failover to the secondary SMS provider, per the existing runbook. |
| 17:40 | **Full recovery.** Delivery rate at 99.6%. |
| 17:45 | In parallel: the on-call SRE checks Prometheus targets. `otp-sms` has been `down` since 14:06 with `context deadline exceeded`. |
| 18:15 | Access from `monitoring` is added to the `NetworkPolicy`. Metrics are back. End of the unmonitored period. |

## 4. Root cause

This incident has two causes, and the postmortem focuses on the second:

- **What failed:** message volume exceeded the throughput contracted with the SMS provider.
- **Why we didn't find out:** the monitoring system was blind, and being blind didn't alert.

The first is a capacity problem that was solved with an existing procedure.
The second is what turned a 10-minute degradation into an 80-minute one.

### 5 whys (on detection)

1. **Why did no alert fire?** Because the OTP SLO alerts evaluate the fraction
   of undelivered codes, and from 14:06 there were no metrics: the SLI was "no
   data", not "35% failures".
2. **Why were there no metrics?** Because the `NetworkPolicy` applied at 14:05
   blocked inbound traffic from the `monitoring` namespace to the metrics port.
3. **Why didn't the change account for monitoring?** Because the hardening
   template only listed application traffic. Prometheus scraping is an
   implicit dependency; it wasn't documented anywhere.
4. **Why didn't the post-change check catch it?** Because it checked that the
   service responded, not that it was still observable. The change checklist
   didn't include "monitoring targets are still `up`".
5. **Why did 4 hours without metrics generate no alert?** Because every alert
   was about the value of metrics and none about their absence. There was no
   `up == 0` or `absent()` alert for services with an SLO, and Grafana showed
   "no data" as a blank panel, not a red one.

**Root cause:** the monitoring system had a silent failure mode —absence of
data meant absence of alerts— and a network change removed a critical
service's telemetry without anything verifying it.

### Contributing factors

- **The campaign wasn't on SRE's calendar.** A predictable 2× volume increase
  was never checked against the provider's contracted capacity.
- **Support attributed the first complaints to carriers**, the most frequent
  cause of "my SMS isn't arriving". Without an alert saying otherwise, it was a
  reasonable conclusion.
- **The provider's contracted throughput wasn't monitored** as a limit: the
  `429`s were in the logs, but weren't counted as a metric.

## 5. What went well

- **Support escalated.** Without monitoring, the support channel was the only
  detection system that worked, and it worked.
- **The failover runbook to the secondary provider existed and was up to
  date.** Once decided, mitigation took 9 minutes.
- **Logs took a different path** (the log agent isn't affected by the
  `NetworkPolicy`): with them the `429`s were found in 6 minutes.
- The War Room separated the two causes in time: impact was mitigated first,
  monitoring fixed second, without mixing the two fronts.

## 6. What went wrong

- **4 hours and 10 minutes without observing a critical service**, and nobody knew.
- **42 minutes of impact before detection**, against the ~5 the burn-rate alert
  would have taken with metrics.
- **The network change was signed off with a functional check.** Observability
  wasn't part of the definition of "the change went fine".
- A blank panel looks like a calm panel.

## 7. Where we got lucky

- **The failure was partial (35%).** With 100% of codes undelivered, nobody
  could have signed in, and the same detection time would have been a P1 with
  total impact for 42 minutes.
- **The contract with the secondary provider was active.** Cancelling it to
  save costs had been considered the previous quarter.

## 8. Action items

| # | Action | Type | Owner | Due | Status |
|---|---|---|---|---|---|
| 1 | `up == 0` or `absent(up)` alert for 1 minute, page severity, for every service with an SLO | Detect | SRE | 2026-09-03 | Closed |
| 2 | SLO panels in Grafana: "no data" is shown in red with the text "NO METRICS", never blank | Detect | SRE | 2026-09-03 | Closed |
| 3 | The `NetworkPolicy` template includes ingress from `monitoring` to the metrics port | Prevent | Security + Platform | 2026-09-10 | Closed |
| 4 | Manifest CI test: every `NetworkPolicy` in a namespace with a `ServiceMonitor` must allow scraping | Prevent | Platform | 2026-09-30 | In progress |
| 5 | The post-change checklist includes "the service's monitoring targets are still `up`" | Prevent | Change Management | 2026-09-10 | Closed |
| 6 | Metric and alert on `429` responses from the SMS provider: above 1% for 5 minutes | Detect | Identity | 2026-09-17 | Open |
| 7 | Automatic failover to the secondary provider if the delivery rate drops below 95% for 3 minutes | Mitigate | Identity | 2026-10-31 | Open |
| 8 | Campaigns with mandatory sign-in go on SRE's capacity calendar 7 days in advance | Prevent | Marketing + SRE | 2026-09-17 | Closed |
| 9 | Runbook [service without metrics](../../runbooks/en/service-without-metrics.md) | Mitigate | SRE | 2026-09-03 | Closed |

## 9. Lessons learned

- **An alerting system has to alert about itself too.** Alerts on a metric's
  value assume the metric exists. When it doesn't, silence reads as "all good",
  and that's the worst possible reading.
- **A blank panel looks just like a calm one.** On a dashboard, missing data
  has to be the most visible thing on the screen.
- **"The change went fine" includes "we can still see the service".** A check
  that only exercises the functional path leaves out half the system.

## Appendix

- Runbooks used: SMS provider failover (internal) and, created from this
  incident, [service without metrics](../../runbooks/en/service-without-metrics.md)
- The alert from action 1 is implemented and tested in the
  [sre-slo-lab](https://github.com/seamnex/sre-slo-lab) as `SLOSinDatos`.
- Target status that confirmed the diagnosis:

  ```console
  $ curl -s localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="otp-sms") | {health, lastError}'
  {
    "health": "down",
    "lastError": "Get \"http://10.42.3.17:9102/metrics\": context deadline exceeded"
  }
  ```
