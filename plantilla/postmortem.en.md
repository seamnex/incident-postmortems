# Postmortem: [short title that describes the impact, not the cause]

[Español](postmortem.es.md) · **English**

<!--
Blameless postmortem template.

Writing rules:
- Describe systems, decisions and signals, never people. "The deploy was
  approved without check X", not "John approved the deploy without looking".
  If someone made a bad call with the information they had, the problem is
  the information they had.
- Every impact claim carries a number and where it came from.
- Write the root cause after the timeline, not before. Writing the cause
  first tempts you to order the facts so they confirm it.
- Every action has an owner (a role or team) and a date. An action without
  a date is a wish.
-->

| | |
|---|---|
| **ID** | INC-YYYY-NNN |
| **Severity** | P1 / P2 / P3 |
| **Status** | Draft · In review · Closed |
| **Incident date** | YYYY-MM-DD |
| **Impact duration** | HH:MM (from the first sign of impact to full recovery) |
| **Time to detect (MTTD)** | HH:MM (from impact start to the first alert or report) |
| **Time to mitigate** | HH:MM (from detection to end of impact) |
| **Affected services** | |
| **Incident Manager** | role |
| **Document authors** | role(s) |
| **Reviewed by** | role(s) — date |

## 1. Executive summary

<!--
Three to five sentences for a non-technical reader who won't read the rest:
what happened, who was affected, for how long, why it happened (one line)
and what will be done so it doesn't happen again.
-->

## 2. Impact

<!--
Quantified. Users, transactions, money, SLO.
-->

| Dimension | Value | Source |
|---|---|---|
| Affected users | | |
| Failed or delayed transactions | | |
| Error budget consumed | % of the monthly budget of SLO X | |
| Estimated financial impact | | |
| Contractual commitments (SLA) | | |

## 3. Timeline

<!--
Explicit time zone. Each entry: what happened and how it became known. Mark
the milestones: impact start, detection, declaration, mitigation, recovery.
-->

All times in UTC-3.

| Time | Event |
|---|---|
| HH:MM | **Impact starts.** |
| HH:MM | **Detection.** |
| HH:MM | Incident declared (Pn), War Room opened. |
| HH:MM | **Mitigation.** |
| HH:MM | **Full recovery.** |

## 4. Root cause

### 5 whys

<!--
Each "why" rests on evidence (log, metric, commit, config), not on
assumptions. If an answer is "human error", you haven't reached the cause
yet: the next question is why the system allowed that error.
-->

1. **Why ...?** Because ...
2. **Why ...?** Because ...
3. **Why ...?** Because ...
4. **Why ...?** Because ...
5. **Why ...?** Because ...

**Root cause:**

### Contributing factors

<!--
What didn't cause the incident but made it longer, worse or harder to
diagnose.
-->

-

## 5. What went well

-

## 6. What went wrong

-

## 7. Where we got lucky

<!--
What went well without anyone having designed it that way. It is the most
honest section of the document and the one that generates the most actions.
-->

-

## 8. Action items

<!--
Type: Prevent (it doesn't happen again) · Detect (we find out sooner) ·
Mitigate (it hurts less if it happens). If they are all of one type, keep
looking.
-->

| # | Action | Type | Owner | Due | Status |
|---|---|---|---|---|---|
| 1 | | Prevent | | | Open |
| 2 | | Detect | | | Open |
| 3 | | Mitigate | | | Open |

## 9. Lessons learned

-

## Appendix

- Runbook used:
- Dashboards:
- War Room thread / channel:
