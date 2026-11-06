# Postmortem: consultas de saldo lentas durante 58 minutos después de un deploy

**Español** · [English](../en/2026-05-19-connection-pool-latency.md)

> **Incidente simulado.** Pagoya y todo lo que describe este documento son
> ficticios: es un ejercicio de redacción de postmortems, no un incidente real.
> Ver el [aviso del repositorio](../../README.md#aviso).

| | |
|---|---|
| **ID** | INC-2026-019 |
| **Severidad** | P2 |
| **Estado** | Cerrado |
| **Fecha del incidente** | 2026-05-19 (martes) |
| **Duración del impacto** | 58 min (10:40 → 11:38) |
| **Tiempo de detección (MTTD)** | 12 min |
| **Tiempo de mitigación** | 46 min |
| **Servicios afectados** | `api-cuentas` (saldo y movimientos) |
| **Incident Manager** | Incident Manager de guardia |
| **Autoría del documento** | Incident Manager, Líder técnico de Cuentas |
| **Revisado por** | Equipo de Cuentas, SRE — 2026-05-22 |

## 1. Resumen ejecutivo

Entre las 10:40 y las 11:38 del martes 19 de mayo, la consulta de saldo y
movimientos de la app tardó entre 2 y 5 segundos en lugar de los 150 ms
habituales, y el 1,8 % de las consultas terminó en error por timeout. Ningún
dinero se perdió ni se movió de forma incorrecta. La causa fue un cambio
desplegado a las 10:40 que retenía una conexión a la base de datos mientras
esperaba la respuesta del servicio antifraude. Con el tráfico de media mañana,
las conexiones se agotaron. Se resolvió con un rollback. Para que no se repita
vamos a desplegar primero a una fracción del tráfico, con una compuerta
automática sobre la latencia.

## 2. Impacto

| Dimensión | Valor | Fuente |
|---|---|---|
| Usuarios afectados | ~41.000 con al menos una consulta lenta | Usuarios únicos en la ventana del incidente |
| Consultas lentas (> 300 ms) | 612.000 de 694.000 (88 %) | Histograma `http_request_duration_seconds` de `api-cuentas` |
| Consultas fallidas (timeout de la app a 5 s) | 12.500 (1,8 %) | `http_requests_total{code="504"}` |
| Error budget consumido — **SLO de latencia** (99 % < 300 ms) | **41 %** del budget mensual | Recording rule `slo:sli_errores:ratio_rate30d` |
| Error budget consumido — SLO de disponibilidad (99,5 %) | 1,7 % del budget mensual | Ídem |
| Impacto económico | Sin pérdida directa: solo lectura | — |
| Contactos a soporte | 214 | Sistema de tickets, categoría "saldo" |

## 3. Línea de tiempo

Todas las horas en UTC-3.

| Hora | Evento |
|---|---|
| 10:34 | Comienza el deploy de `api-cuentas` v4.18 (rolling update, 6 pods en 6 minutos). Incluye la nueva sección "movimientos recientes con score de riesgo" y una migración que agrega una columna. |
| 10:40 | **Inicio del impacto.** Termina el rollout. El p99 de `api-cuentas` sube de 180 ms a 2,4 s. |
| 10:52 | **Detección.** Dispara `SLOQuemaRapida` del SLO de latencia (burn rate 18×). Page al SRE de guardia. |
| 10:55 | El SRE de guardia ve la correlación con el deploy en el dashboard (anotación de deploy a las 10:34). |
| 10:58 | **Se declara el incidente P2.** War Room con SRE, Incident Manager y Líder técnico de Cuentas. |
| 11:02 | Primera hipótesis: la migración bloqueó la tabla. Se revisa la base: CPU al 35 %, sin locks largos, sin queries lentas. Se descarta. |
| 11:09 | El Líder técnico revisa el panel de saturación de recursos: **el pool de conexiones está al 100 % en los 6 pods** (20 de 20) y hay 340 pedidos esperando una conexión. |
| 11:11 | Se propone rollback. Se frena: la versión incluyó una migración y **nadie en el War Room puede confirmar si la v4.17 funciona con la columna nueva.** |
| 11:24 | El autor de la migración confirma que es aditiva (columna nueva, nullable, sin default) y que la v4.17 la ignora. |
| 11:31 | **Mitigación.** Rollback a v4.17. |
| 11:38 | **Recuperación total.** Pool de conexiones al 30 %, p99 en 170 ms. |
| 11:50 | Se cierra el War Room. |
| 14:20 | Se confirma la causa con un profiler en staging: cada consulta de movimientos retiene la conexión ~800 ms, el tiempo que tarda el servicio antifraude. |

## 4. Causa raíz

### 5 porqués

1. **¿Por qué las consultas tardaban segundos?** Porque esperaban una conexión
   libre a la base de datos: el pool estaba al 100 % en los seis pods.
2. **¿Por qué se agotó el pool?** Porque el endpoint nuevo abría una
   transacción, leía los movimientos y **dentro de la misma transacción**
   llamaba de forma sincrónica al servicio antifraude (p50 de 600 ms). La
   conexión quedaba retenida todo ese tiempo, 40 veces más que antes.
3. **¿Por qué no lo detectaron los tests ni la revisión de código?** Porque en
   el entorno de pruebas de carga el servicio antifraude es un mock que
   responde en 5 ms: el patrón era invisible con esa latencia. En la revisión
   de código, el alcance de la transacción no estaba a la vista: lo define una
   anotación en otro archivo.
4. **¿Por qué llegó al 100 % del tráfico antes de que algo lo frenara?** Porque
   el deploy es un rolling update que cubre todo el tráfico en 6 minutos, sin
   una etapa canary ni una compuerta automática sobre la latencia.
5. **¿Por qué la primera señal fue la alerta de SLO y no la saturación del
   pool?** Porque las métricas del pool se exportaban pero no tenían alerta. La
   saturación del pool es un indicador adelantado: llegó al 100 % a las 10:38 y
   la alerta de SLO disparó 14 minutos después.

**Causa raíz:** un cambio de código retenía conexiones a la base durante una
llamada externa lenta. El entorno de pruebas no reproducía la latencia real de
esa dependencia, y el proceso de deploy no tenía una etapa que expusiera el
cambio a una fracción del tráfico antes de llevarlo al 100 %.

### Factores contribuyentes

- **La reversibilidad de la migración no estaba documentada.** Costó 20
  minutos de impacto confirmar algo que el autor sabía desde el principio.
- **La llamada al servicio antifraude no tenía timeout propio**: usaba el
  default del cliente HTTP, de 30 segundos.
- **El panel de saturación existía, pero no estaba en el dashboard principal.**
  Se encontró a los 17 minutos del War Room.

## 5. Qué salió bien

- **La alerta de SLO detectó el problema antes que los usuarios.** Los primeros
  tickets de soporte llegaron a las 11:05, 13 minutos después del page.
- La anotación del deploy en el dashboard hizo evidente la correlación en 3
  minutos.
- La hipótesis de la migración se descartó con evidencia (CPU, locks, queries
  lentas) en 7 minutos, en lugar de actuar sobre ella.
- El rollback, una vez decidido, tardó 7 minutos y funcionó a la primera.

## 6. Qué salió mal

- **20 minutos de impacto evitables** esperando confirmar que el rollback era
  seguro.
- **La señal de saturación estaba disponible y no se miró primero.** Se empezó
  por la base de datos —el sospechoso habitual— y no por el recurso que se
  estaba agotando.
- **El cambio fue al 100 % del tráfico de una vez.** Con un canary del 10 %,
  el impacto habría sido una décima parte y el rollback, automático.

## 7. Dónde tuvimos suerte

- **La migración era aditiva.** Si hubiera renombrado o eliminado una columna,
  el rollback habría sido imposible sin una segunda migración, y el impacto
  habría durado lo que tardara escribirla y probarla.
- **No era día de cobro.** El tráfico de consultas de saldo en los días 1 y
  15 de cada mes es unas 3 veces el de un martes común. Con ese volumen, el
  pool se habría agotado en el primer minuto y los timeouts habrían sido
  mayoría, no el 1,8 %.

## 8. Acciones

| # | Acción | Tipo | Responsable | Fecha | Estado |
|---|---|---|---|---|---|
| 1 | Etapa canary del 10 % durante 15 minutos, con rollback automático si el burn rate del SLO de latencia supera 6× | Mitigar | Plataforma | 2026-06-30 | En curso |
| 2 | Alerta de saturación del pool de conexiones: más del 80 % durante 5 minutos | Detectar | SRE | 2026-05-29 | Cerrada |
| 3 | Panel de saturación (pool, threads, CPU) en el dashboard principal de cada servicio | Detectar | SRE | 2026-05-29 | Cerrada |
| 4 | El mock del servicio antifraude en pruebas de carga reproduce la distribución de latencia de producción | Prevenir | QA + Cuentas | 2026-06-15 | Abierta |
| 5 | Regla de revisión de código y chequeo estático: ninguna llamada de red dentro de una transacción de base de datos | Prevenir | Cuentas | 2026-06-15 | En curso |
| 6 | La plantilla de PR exige declarar si la migración es reversible y si la versión anterior es compatible | Mitigar | Arquitectura | 2026-05-29 | Cerrada |
| 7 | Timeout de 300 ms y circuit breaker en la llamada al servicio antifraude, con degradación a "score no disponible" | Mitigar | Cuentas | 2026-06-15 | Abierta |

## 9. Lecciones

- **Ante un problema de latencia, primero se mira qué recurso se está
  saturando**, no qué componente suele fallar. La base era el sospechoso
  habitual y estaba sana; el pool, que nadie miraba, estaba al 100 %.
- **Un mock más rápido que la dependencia real esconde exactamente esta clase
  de error.** Las pruebas de carga miden lo que el entorno de pruebas les deja
  ver.
- **La pregunta "¿podemos hacer rollback?" se contesta antes del deploy, no en
  el War Room.**

## Anexos

- Runbook usado: [quema de error budget](../../runbooks/es/quema-de-error-budget.md), sección "Latencia"
- Consulta que mostró la saturación:

  ```promql
  max by (pod) (db_pool_connections_in_use{service="api-cuentas"})
    / max by (pod) (db_pool_connections_max{service="api-cuentas"})
  ```
