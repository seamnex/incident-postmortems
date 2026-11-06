# Runbook: quema de error budget

**Español** · [English](../en/error-budget-burn.md)

> Ejercicio de práctica. Los nombres de servicios y dashboards son los del
> [sre-slo-lab](https://github.com/seamnex/sre-slo-lab) y los de la empresa
> ficticia de los postmortems de este repositorio.

| | |
|---|---|
| **Alertas** | `SLOQuemaRapida` (page) · `SLOQuemaLenta` (ticket) |
| **Qué significa** | Un SLO está consumiendo su error budget más rápido de lo sostenible. La etiqueta `slo` dice cuál: `disponibilidad` o `latencia`. |
| **Urgencia** | **Page:** el budget se agota en días. Actuar ahora. **Ticket:** se agota en semanas. Resolver en horario laboral. |
| **Dashboard** | Grafana → *SLOs — Checkout* |
| **Usado en** | [INC-2026-019](../../postmortems/es/2026-05-19-latencia-pool-de-conexiones.md) |

---

## Primeros 5 minutos

El objetivo de estos 5 minutos **no es encontrar la causa**: es dimensionar el
impacto y decidir si se declara un incidente.

1. **Confirmar que es real.** En el dashboard, mirar el burn rate de 5 min del
   SLO de la alerta. Si ya bajó de 1×, el problema terminó solo: seguir con
   [Después](#después) y no declarar nada.

2. **Dimensionar.** ¿Qué fracción de los pedidos está fallando o lenta?

   ```promql
   slo:sli_errores:ratio_rate5m
   ```

3. **Buscar un cambio reciente.** Es la causa más frecuente y la más rápida de
   revertir.
   - Deploys en las últimas 2 horas (anotaciones del dashboard, historial del
     pipeline de CD).
   - Cambios de configuración, feature flags, migraciones.
   - Cambios de infraestructura: red, certificados, secretos.

4. **Decidir.** Si es una alerta de page y el impacto sigue activo, **declarar
   el incidente** y abrir el War Room. Es mejor declarar y cerrar a los 10
   minutos que no declarar y descubrir a los 40 que era un P1.

## Diagnóstico

### Si `slo="disponibilidad"` — errores 5xx

1. ¿Qué códigos? ¿Todos los endpoints o uno solo?

   ```promql
   sum by (code) (rate(http_requests_total{job="checkout"}[5m]))
   ```

2. ¿Es el servicio o una dependencia? Buscar en los logs de los últimos 15
   minutos los errores más repetidos. Un error de conexión o de TLS hacia una
   dependencia apunta afuera; una excepción propia apunta al código.

3. Si apunta a una dependencia externa: revisar su página de estado **y en
   paralelo** verificar lo propio que la conecta (credenciales, certificados,
   DNS). Ver [certificado TLS por vencer o vencido](certificado-tls-por-vencer.md).

### Si `slo="latencia"` — pedidos de más de 300 ms

Ante un problema de latencia, **primero se mira qué recurso se está saturando**,
no qué componente suele fallar.

1. Saturación, en este orden: pool de conexiones a la base, threads o workers,
   CPU, memoria.

   ```promql
   max by (pod) (db_pool_connections_in_use / db_pool_connections_max)
   ```

2. Latencia de las dependencias: ¿alguna llamada externa se volvió lenta? Un
   servicio que espera a otro hereda su latencia.

3. ¿Cambió el tráfico? Un pico de volumen sobre un sistema sano también
   satura recursos.

   ```promql
   sum(rate(http_requests_total{job="checkout"}[5m]))
   ```

## Mitigación

En este orden de preferencia. **Mitigar primero, entender después**: la causa
raíz se busca con el impacto ya contenido.

| Si... | Hacer | Verificar antes |
|---|---|---|
| Hay un deploy o cambio correlacionado | **Rollback** | ¿El cambio incluyó una migración? ¿Es compatible con la versión anterior? Si no se sabe, preguntarle al autor *ya*, en paralelo |
| El cambio está detrás de un feature flag | Apagar el flag | — |
| Hay saturación por volumen | Escalar horizontalmente | Que el cuello de botella no sea compartido (una base no escala con más pods: escalar pods puede empeorarlo) |
| Falla una dependencia con alternativa | Failover a la alternativa | Que la alternativa tenga capacidad |
| Falla una dependencia sin alternativa | Degradar: desactivar la funcionalidad que depende de ella | Comunicar qué queda sin funcionar |

## Verificación

El incidente está mitigado cuando:

- [ ] El burn rate de 5 min está por debajo de 1×.
- [ ] La alerta pasa a `resolved` (con la ventana corta de 5 min, tarda pocos minutos).
- [ ] El tráfico volvió a su volumen normal: un SLI sano con la mitad del tráfico
      puede significar que los usuarios dejaron de intentar.

## Escalamiento

| Después de | Sin mitigación | Escalar a |
|---|---|---|
| 15 min | Sin hipótesis | Líder técnico del servicio |
| 30 min | Sin mitigación | Incident Manager decide si sube la severidad |
| En cualquier momento | La causa es una dependencia de otro equipo | Guardia de ese equipo, con el dashboard y la evidencia |

## Comunicación

- **Página de estado:** primera comunicación a los 15 minutos de declarado,
  aunque todavía no haya causa: qué funciona, qué no, y cuándo será la próxima
  actualización.
- **Actualizaciones:** cada 30 minutos mientras dure el impacto.

## Después

- Registrar cuánto error budget se consumió:

  ```promql
  1 - slo:error_budget_restante:ratio
  ```

- Postmortem obligatorio si el incidente consumió más del 10 % del budget
  mensual o fue declarado P1. Usar la [plantilla](../../plantilla/postmortem.es.md).
- Si la alerta fue una `SLOQuemaLenta` sin incidente: abrir un ticket con el
  burn rate observado y la causa probable. Es deuda que se paga antes de que se
  convierta en un page.
