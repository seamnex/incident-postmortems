# Postmortem: card payments rejected for 2 h 38 min

[Español](../es/2026-03-14-certificado-mtls-vencido.md) · **English**

> **Simulated incident.** Pagoya and everything described in this document are
> fictional: this is a postmortem-writing exercise, not a real incident.
> See the [repository notice](../../README.en.md#notice).

| | |
|---|---|
| **ID** | INC-2026-007 |
| **Severity** | P1 |
| **Status** | Closed |
| **Incident date** | 2026-03-14 (Saturday) |
| **Impact duration** | 2 h 38 min (03:00 → 05:38) |
| **Time to detect (MTTD)** | 7 min |
| **Time to mitigate** | 2 h 31 min |
| **Affected services** | `pagos-gateway` → external card processor |
| **Incident Manager** | On-call Incident Manager |
| **Document authors** | Incident Manager, on-call SRE |
| **Reviewed by** | Payments Tech Lead, Security — 2026-03-18 |

## 1. Executive summary

Between 03:00 and 05:38 on Saturday, March 14, **100% of card payments
failed**: 3,140 transactions from 2,287 users. Wallet-to-wallet transfers were
not affected. The cause was the expiry of the client certificate Pagoya uses to
authenticate with the card processor (mTLS). An automated job was supposed to
renew it, but it had been failing silently for 53 days. To prevent a repeat we
will monitor the expiry of **all** certificates, internal ones included, and
alert when a renewal job stops completing.

## 2. Impact

| Dimension | Value | Source |
|---|---|---|
| Affected users | 2,287 | Unique users with at least one rejected payment |
| Failed card payments | 3,140 (100% of the period) | `pagos-gateway` logs, code `502` |
| Payments successfully retried after recovery | 1,912 (61%) | Matched by user and merchant, up to 24 h later |
| Error budget consumed | **15%** of the monthly budget of the card payments SLO (99.5%) | 3,140 failures / 21,000 allowed in 30 days |
| Estimated financial impact | Fees on 1,228 unrecovered payments | Finance, based on the average ticket |
| Merchant SLA | No breach: the SLA is monthly and closed at 99.93% | March SLA report |

## 3. Timeline

All times in UTC-3.

| Time | Event |
|---|---|
| 01/20 | Security rotates the processor API token as part of the quarterly rotation. The certificate renewal job keeps using the old token. |
| 01/21 → 03/13 | The renewal job runs every night and fails with `401 Unauthorized`. **53 consecutive failures, zero alerts.** |
| 03/14 03:00 | **Impact starts.** The mTLS client certificate expires. The processor rejects the handshake and `pagos-gateway` returns `502` for every card payment. |
| 03:07 | **Detection.** `SLOQuemaRapida` fires for the card payments SLO (burn rate 200×). The on-call SRE is paged. |
| 03:12 | The on-call SRE confirms on the dashboard: 100% errors on card payments, transfers normal. |
| 03:15 | **P1 incident declared**, War Room opened. The Incident Manager is called in. |
| 03:18 | First hypothesis: processor outage. Logs show `remote error: tls: handshake failure`, consistent with a problem on the processor side. |
| 03:30 | First status page update: "Card payments are failing. Transfers are working normally." |
| 03:35 | The processor's status page is green. A critical-priority case is opened with the processor. |
| 03:46 | The on-call SRE checks the client certificate with `openssl x509 -enddate`: **it expired at 03:00.** The processor hypothesis is dropped (28 min after it was formed). |
| 03:52 | The renewal job is run by hand: it fails with `401`. The token rotated in January is identified. |
| 04:05 | With the current token the job generates the CSR, but **the certificate is signed by the processor**: it can't be completed from Pagoya. |
| 04:10 | The processor confirms the expiry by phone and escalates the emergency signing to its on-call team. |
| 05:20 | The processor delivers the signed certificate. |
| 05:32 | **Mitigation.** The cluster secret is updated and the `pagos-gateway` pods are restarted one at a time. |
| 05:38 | **Full recovery.** Card payment success rate at 99.8%, same as baseline. |
| 06:10 | War Room closed. Resolution posted on the status page. |

## 4. Root cause

### 5 whys

1. **Why did card payments fail?** Because the processor rejected the mTLS
   handshake: Pagoya's client certificate expired at 03:00.
2. **Why did the certificate expire?** Because the job that renews it 7 days
   before expiry didn't renew it.
3. **Why didn't it renew it?** Because it authenticates against the processor
   API with a token that Security rotated on January 20, and the job still had
   the old one. It failed with `401` for the next 53 nights.
4. **Why did nobody notice 53 failures?** Because the job wrote the error to a
   log nobody read and exited with code 0: as far as the scheduler knew, every
   run succeeded. There was no alert on the job's outcome nor on the
   certificate's expiry date.
5. **Why was there no expiry alert?** Because the inventory of monitored
   certificates only covered public TLS certificates (website and API). The
   mTLS client certificate lived as a cluster secret, outside the inventory,
   with no defined owning team: Payments assumed it belonged to Platform, and
   Platform assumed it belonged to Payments.

**Root cause:** the renewal of a critical credential depended on a job that
could fail silently, with no monitoring of its execution nor of the outcome
that matters (the expiry date), and the credential was not in any inventory
with an assigned owner.

### Contributing factors

- **The token rotation didn't list its consumers.** Security's rotation
  procedure updated the known applications; the renewal job wasn't on the list.
- **Signing depends on a third party.** Even with the right diagnosis, recovery
  couldn't be faster than the processor's response time (1 h 10 min).
- **The error message was ambiguous.** `tls: handshake failure` doesn't say
  which side is failing. "The processor is down" was a reasonable hypothesis
  with that evidence, and it took 28 minutes to rule out.
- **There was no runbook** for certificate failures.

## 5. What went well

- **The SLO alert detected the impact in 7 minutes**, at 3 a.m. on a Saturday,
  without waiting for a customer to call.
- The dashboard separated card payments from transfers: within 5 minutes the
  impact was known to be contained, and the first update said so precisely.
- The critical case with the processor was opened in parallel with the
  diagnosis, not after it. When the cause was confirmed, the processor was
  already engaged.
- Pods were restarted one at a time: the few payments that arrived during the
  mitigation didn't add new errors.

## 6. What went wrong

- **A hypothesis was held for 28 minutes without looking for contrary
  evidence.** The check that ruled it out —reading the certificate's date—
  takes 30 seconds.
- **Nobody knew who owned the certificate.** The first half hour of diagnosis
  was also a search for the owner.
- **Emergency renewal had no agreed procedure** with the processor. It was
  solved by phone and goodwill.
- **53 consecutive job failures without a single alert.** The system had
  almost two months to warn us and never did.

## 7. Where we got lucky

- **It happened at 3 a.m. on a Saturday.** Card payment volume at that hour is
  roughly 1/12 of a weekday noon. The same incident on a Tuesday at 12:00 would
  have hit around 37,000 payments and burned the whole month's error budget in
  about an hour and a half.
- **The processor's on-call team picked up the phone** and agreed to sign
  outside their usual process. Nothing in place guaranteed it.

## 8. Action items

| # | Action | Type | Owner | Due | Status |
|---|---|---|---|---|---|
| 1 | Alert on the expiry of **all** certificates (public, mTLS and internal) at 30, 14 and 7 days | Detect | SRE / Platform | 2026-03-28 | Closed |
| 2 | The renewal job exits non-zero on any error, and a *dead man's switch* alert fires if there was no successful run in 48 h | Detect | Platform | 2026-03-28 | Closed |
| 3 | Versioned inventory of certificates and credentials with owning team, expiry date and renewal procedure | Prevent | Security + Payments | 2026-04-15 | In progress |
| 4 | Renew 30 days before expiry instead of 7 | Prevent | Payments | 2026-04-01 | Closed |
| 5 | The token rotation procedure requires listing its consumers and verifying each one after rotating | Prevent | Security | 2026-04-15 | In progress |
| 6 | Agree an emergency signing procedure with the processor, with a committed response time | Mitigate | Partner Management | 2026-04-30 | Open |
| 7 | Runbook [TLS certificate expiring or expired](../../runbooks/en/tls-certificate-expiring.md) | Mitigate | SRE | 2026-03-21 | Closed |

## 9. Lessons learned

- **An automated job that can fail silently is a time bomb with a hidden
  fuse.** Automating the renewal isn't enough: you have to monitor the
  *outcome* (the expiry date), not just the execution.
- **Every credential needs an owner.** "Everyone's" means "nobody's", measured
  in War Room minutes.
- **The first diagnostic step is the cheapest thing to check, not the most
  likely one.** Reading a certificate's date takes 30 seconds; ruling out a
  processor outage took 28 minutes.

## Appendix

- Runbook created from this incident: [TLS certificate expiring or expired](../../runbooks/en/tls-certificate-expiring.md)
- The check that confirmed the cause:

  ```bash
  kubectl get secret pagos-procesador-mtls -n pagos -o jsonpath='{.data.tls\.crt}' \
    | base64 -d | openssl x509 -noout -enddate
  # notAfter=Mar 14 06:00:00 2026 GMT     (03:00 UTC-3)
  ```
