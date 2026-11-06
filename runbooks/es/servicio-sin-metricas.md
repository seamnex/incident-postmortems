# Runbook: servicio sin métricas

**Español** · [English](../en/service-without-metrics.md)

> Ejercicio de práctica. Los nombres de servicios y dashboards son los del
> [sre-slo-lab](https://github.com/seamnex/sre-slo-lab) y los de la empresa
> ficticia de los postmortems de este repositorio.

| | |
|---|---|
| **Alerta** | `SLOSinDatos` (page) |
| **Qué significa** | Prometheus no puede leer las métricas de un servicio con SLO. **Mientras dure, las alertas de burn rate de ese servicio están ciegas**: la ausencia de alertas no significa que el servicio esté bien. |
| **Urgencia** | Alta. Puede ser una caída total del servicio, o puede ser que el servicio funciona y no lo estamos viendo. Las dos se atienden ya. |
| **Creado a partir de** | [INC-2026-031](../../postmortems/es/2026-08-27-monitoreo-ciego-otp.md) |

---

## Primeros 5 minutos: ¿caído o ciego?

La alerta tiene dos causas posibles con consecuencias muy distintas. Lo
primero es separarlas.

1. **¿El servicio responde?** Probar el camino del usuario, no el health check:

   ```bash
   curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://<servicio>/api/checkout
   ```

   - **No responde, o responde 5xx** → **está caído.** Declarar incidente y
     seguir el runbook de [quema de error budget](quema-de-error-budget.md):
     el impacto es total, aunque ninguna alerta de burn rate lo diga.
   - **Responde bien** → **estamos ciegos.** Seguir con el diagnóstico de abajo.

2. **¿Qué dice Prometheus del target?**

   ```bash
   curl -s localhost:9090/api/v1/targets \
     | jq '.data.activeTargets[] | select(.labels.job=="checkout") | {health, lastError, lastScrape}'
   ```

   | `lastError` | Causa probable |
   |---|---|
   | `context deadline exceeded` | Algo bloquea la conexión: `NetworkPolicy`, firewall, security group |
   | `connection refused` | El puerto de métricas no escucha: el proceso cambió de puerto o no expone `/metrics` |
   | `no such host` | DNS: el servicio cambió de nombre o de namespace |
   | `server returned HTTP status 401/403` | Se agregó autenticación al endpoint de métricas |
   | *(el target no aparece)* | Cambió el service discovery: labels, anotaciones, `ServiceMonitor` |

## Diagnóstico — si estamos ciegos

1. **¿Qué cambió?** Buscar cambios en la última ventana desde que el target
   pasó a `down` (`lastScrape` dice cuándo fue el último exitoso): políticas de
   red, versiones del servicio, configuración de Prometheus.

2. **Probar el scrape desde donde lo hace Prometheus**, no desde la máquina
   propia:

   ```bash
   kubectl exec -n monitoring deploy/prometheus -- \
     wget -qO- -T 5 http://<ip-del-pod>:<puerto>/metrics | head
   ```

   Si falla desde ahí y funciona desde otro lado, es la red.

3. **Revisar las `NetworkPolicy` del namespace del servicio:**

   ```bash
   kubectl get networkpolicy -n <namespace> -o yaml
   ```

   ¿Hay una regla de ingreso que permita el tráfico desde el namespace
   `monitoring` al puerto de métricas?

## Mitigación

1. **Mientras esté ciego, alguien mira a mano.** Verificar el camino del
   usuario cada 5 minutos y registrar el resultado en el canal del incidente.
   No es elegante, pero es lo único que reemplaza a la alerta que no funciona.
2. **Restaurar el scrape** con el cambio mínimo: agregar la regla de ingreso,
   revertir el cambio de puerto, corregir el label. La solución de fondo puede
   esperar al postmortem; la visibilidad, no.
3. Si no se puede restaurar rápido: buscar una señal alternativa (logs,
   métricas del balanceador, métricas del lado del cliente) y crear una alerta
   temporal sobre ella.

## Verificación

- [ ] El target figura `up` en Prometheus.
- [ ] `SLOSinDatos` pasa a `resolved`.
- [ ] Los SLIs del servicio vuelven a tener valor:

  ```promql
  slo:sli_errores:ratio_rate5m
  ```

- [ ] **Mirar el período ciego.** Con las métricas de vuelta, revisar si hubo
      impacto mientras no se veía nada: logs, tickets de soporte, métricas
      de las dependencias. El período sin datos no es un período sin
      incidentes; es un período sin evidencia.

## Después

- Postmortem si el período ciego duró más de 30 minutos, aunque no haya habido
  impacto: un monitoreo que se puede romper sin que nadie se entere se va a
  volver a romper.
- Si la causa fue un cambio: agregar al checklist de ese tipo de cambio
  "verificar que los targets de monitoreo siguen `up`".
