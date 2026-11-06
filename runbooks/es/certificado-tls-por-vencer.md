# Runbook: certificado TLS por vencer o vencido

**Español** · [English](../en/tls-certificate-expiring.md)

> Ejercicio de práctica. Los nombres de servicios, secrets y del procesador de
> pagos son los de la empresa ficticia de los postmortems de este repositorio.

| | |
|---|---|
| **Alertas** | `CertificadoPorVencer` (ticket a 30 días, page a 7) · errores de handshake TLS hacia una dependencia |
| **Qué significa** | Un certificado está por vencer, o ya venció y una conexión TLS o mTLS empezó a fallar. |
| **Urgencia** | **Vencido:** P1 si afecta un flujo crítico. **Por vencer:** depende de cuánto tarda la renovación; si la firma depende de un tercero, 7 días es poco. |
| **Creado a partir de** | [INC-2026-007](../../postmortems/es/2026-03-14-certificado-mtls-vencido.md) |

---

## Primeros 5 minutos

Ante cualquier error de TLS hacia una dependencia, **lo primero es leer la
fecha de vencimiento**. Son 30 segundos y descartan o confirman la causa más
común. En INC-2026-007 se tardó 28 minutos en hacerlo.

1. **Certificado de un servidor (TLS):**

   ```bash
   echo | openssl s_client -connect <host>:443 -servername <host> 2>/dev/null \
     | openssl x509 -noout -subject -issuer -enddate
   ```

2. **Certificado de cliente guardado como secret (mTLS):**

   ```bash
   kubectl get secret <secret> -n <namespace> -o jsonpath='{.data.tls\.crt}' \
     | base64 -d | openssl x509 -noout -subject -enddate
   ```

3. **Leer el error con atención.** Que el handshake falle no dice de qué lado
   está el problema:

   | Error | Suele indicar |
   |---|---|
   | `certificate has expired` / `certificate verify failed` | El certificado **del servidor** venció o no es de confianza |
   | `tls: bad certificate` / `handshake failure` del lado remoto | El servidor rechazó **nuestro** certificado de cliente: vencido, revocado o de otra CA |
   | `unknown authority` | Falta la CA intermedia o raíz en el bundle |

## Si ya venció: renovación de emergencia

1. **Declarar el incidente** si afecta un flujo crítico. La renovación puede
   tardar más de lo que parece.
2. **Encontrar al responsable** en el inventario de certificados: equipo dueño,
   CA emisora, procedimiento de renovación.
3. **¿Quién firma?**
   - **CA propia o automatizada** (ACME, CA interna): renovar y seguir.
   - **CA de un tercero** (por ejemplo, el procesador de pagos): abrir el caso
     de emergencia **ya**, en paralelo al resto. Ese tiempo de respuesta es el
     piso de la recuperación.
4. **Generar la clave y el CSR**, si el procedimiento no los reutiliza:

   ```bash
   openssl req -new -newkey rsa:2048 -nodes \
     -keyout cliente.key -out cliente.csr -subj "/CN=<cn-acordado>"
   ```

5. **Actualizar el secret y reiniciar de a un pod:**

   ```bash
   kubectl create secret tls <secret> -n <namespace> \
     --cert=cliente.crt --key=cliente.key --dry-run=client -o yaml | kubectl apply -f -
   kubectl rollout restart deployment/<servicio> -n <namespace>
   kubectl rollout status deployment/<servicio> -n <namespace>
   ```

## Si está por vencer: renovación planificada

1. Renovar siguiendo el procedimiento del inventario. Si existe un job
   automático, **averiguar por qué no lo renovó todavía**: un job de
   renovación que no corrió es un incidente que aún no pasó.
2. Desplegar el certificado nuevo **antes** de que venza el anterior, y
   verificar con el comando del paso 1 o 2 que el que está en uso es el nuevo.

## Verificación

- [ ] La fecha de vencimiento del certificado en uso es la nueva.
- [ ] Las conexiones a la dependencia vuelven a funcionar (tasa de éxito en la línea de base).
- [ ] El job de renovación automática corrió con éxito al menos una vez después del arreglo.

## Después

- Si el certificado no estaba en el inventario: agregarlo, con responsable.
- Si el job de renovación falló: el job tiene que terminar con error cuando
  falla, y tiene que existir una alerta si no hubo una corrida exitosa en 48 h.
- Revisar que la alerta de vencimiento cubra este certificado. Si no lo cubría,
  ese es el hallazgo más importante del incidente.
