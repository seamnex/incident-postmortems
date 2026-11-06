# Runbook: TLS certificate expiring or expired

[Español](../es/certificado-tls-por-vencer.md) · **English**

> Practice exercise. Service, secret and payment processor names come from the
> fictional company in this repository's postmortems.

| | |
|---|---|
| **Alerts** | `CertificadoPorVencer` (ticket at 30 days, page at 7) · TLS handshake errors towards a dependency |
| **What it means** | A certificate is about to expire, or already has and a TLS or mTLS connection started failing. |
| **Urgency** | **Expired:** P1 if it affects a critical flow. **Expiring:** depends on how long renewal takes; if signing depends on a third party, 7 days is not much. |
| **Created from** | [INC-2026-007](../../postmortems/en/2026-03-14-expired-mtls-certificate.md) |

---

## First 5 minutes

For any TLS error towards a dependency, **read the expiry date first**. It
takes 30 seconds and confirms or rules out the most common cause. In
INC-2026-007 it took 28 minutes to do it.

1. **Server certificate (TLS):**

   ```bash
   echo | openssl s_client -connect <host>:443 -servername <host> 2>/dev/null \
     | openssl x509 -noout -subject -issuer -enddate
   ```

2. **Client certificate stored as a secret (mTLS):**

   ```bash
   kubectl get secret <secret> -n <namespace> -o jsonpath='{.data.tls\.crt}' \
     | base64 -d | openssl x509 -noout -subject -enddate
   ```

3. **Read the error carefully.** A failing handshake doesn't say which side
   has the problem:

   | Error | Usually means |
   |---|---|
   | `certificate has expired` / `certificate verify failed` | The **server's** certificate expired or isn't trusted |
   | `tls: bad certificate` / remote `handshake failure` | The server rejected **our** client certificate: expired, revoked or from another CA |
   | `unknown authority` | The intermediate or root CA is missing from the bundle |

## If it already expired: emergency renewal

1. **Declare the incident** if it affects a critical flow. Renewal may take
   longer than it looks.
2. **Find the owner** in the certificate inventory: owning team, issuing CA,
   renewal procedure.
3. **Who signs?**
   - **Own or automated CA** (ACME, internal CA): renew and continue.
   - **Third-party CA** (for example, the payment processor): open the
     emergency case **now**, in parallel with everything else. Their response
     time is the floor for recovery.
4. **Generate the key and CSR**, if the procedure doesn't reuse them:

   ```bash
   openssl req -new -newkey rsa:2048 -nodes \
     -keyout client.key -out client.csr -subj "/CN=<agreed-cn>"
   ```

5. **Update the secret and restart one pod at a time:**

   ```bash
   kubectl create secret tls <secret> -n <namespace> \
     --cert=client.crt --key=client.key --dry-run=client -o yaml | kubectl apply -f -
   kubectl rollout restart deployment/<service> -n <namespace>
   kubectl rollout status deployment/<service> -n <namespace>
   ```

## If it's expiring: planned renewal

1. Renew following the inventory's procedure. If there's an automated job,
   **find out why it hasn't renewed it yet**: a renewal job that didn't run is
   an incident that hasn't happened yet.
2. Deploy the new certificate **before** the old one expires, and confirm with
   the command from step 1 or 2 that the one in use is the new one.

## Verification

- [ ] The expiry date of the certificate in use is the new one.
- [ ] Connections to the dependency work again (success rate at baseline).
- [ ] The automated renewal job has run successfully at least once after the fix.

## Afterwards

- If the certificate wasn't in the inventory: add it, with an owner.
- If the renewal job failed: the job has to exit with an error when it fails,
  and there has to be an alert if there was no successful run in 48 h.
- Check that the expiry alert covers this certificate. If it didn't, that's
  the most important finding of the incident.
