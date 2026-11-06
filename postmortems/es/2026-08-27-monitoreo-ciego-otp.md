# Postmortem: códigos OTP sin entregar durante 80 minutos, sin una sola alerta

**Español** · [English](../en/2026-08-27-blind-monitoring-otp.md)

> **Incidente simulado.** Pagoya y todo lo que describe este documento son
> ficticios: es un ejercicio de redacción de postmortems, no un incidente real.
> Ver el [aviso del repositorio](../../README.md#aviso).

| | |
|---|---|
| **ID** | INC-2026-031 |
| **Severidad** | P2 |
| **Estado** | Cerrado |
| **Fecha del incidente** | 2026-08-27 (jueves) |
| **Duración del impacto** | 1 h 20 min (16:20 → 17:40) |
| **Tiempo de detección (MTTD)** | **42 min**, por reclamos de usuarios, no por una alerta |
| **Tiempo de mitigación** | 38 min |
| **Período sin monitoreo** | **4 h 10 min** (14:05 → 18:15) |
| **Servicios afectados** | `otp-sms` (códigos de verificación para el inicio de sesión) |
| **Incident Manager** | Incident Manager de guardia |
| **Autoría del documento** | Incident Manager, SRE de guardia |
| **Revisado por** | SRE, Seguridad, Identidad — 2026-09-01 |

## 1. Resumen ejecutivo

Entre las 16:20 y las 17:40 del jueves 27 de agosto, **el 35 % de los códigos
de verificación por SMS no llegó a los usuarios**, y unos 1.850 no pudieron
iniciar sesión en el primer intento. El proveedor de SMS empezó a limitar
nuestros envíos cuando una campaña de marketing duplicó el volumen. Pero el
problema principal de este incidente no es esa falla: es que **ninguna alerta
la detectó**. Dos horas antes, un cambio de seguridad en la red había cortado
el acceso del sistema de monitoreo al servicio, y la ausencia de métricas no
dispara ninguna alerta. Nos enteramos 42 minutos después, por los reclamos.
Las acciones principales hacen que la falta de datos sea, en sí misma, una alerta.

## 2. Impacto

| Dimensión | Valor | Fuente |
|---|---|---|
| Códigos OTP solicitados | 6.400 | Logs de `otp-sms` (los logs sí llegaron: van por otro camino) |
| Códigos no entregados | 2.240 (35 %) | Reporte de entrega del proveedor |
| Usuarios sin poder iniciar sesión en el primer intento | ~1.850 | Usuarios únicos con OTP no entregado |
| Error budget consumido — SLO de entrega de OTP (99 % en < 30 s) | **13 %** del budget mensual | 2.240 / 17.280 permitidos en 30 días |
| Contactos a soporte | 386 | Sistema de tickets, categoría "no me llega el código" |
| Impacto económico | Sin pérdida directa; costo de la campaña con conversión reducida | Marketing |

## 3. Línea de tiempo

Todas las horas en UTC-3.

| Hora | Evento |
|---|---|
| 14:05 | Se aplica una `NetworkPolicy` de *default-deny* al namespace `otp`, como parte del plan de endurecimiento de Seguridad. La política permite el tráfico de la aplicación, **pero no el de Prometheus** desde el namespace `monitoring`. |
| 14:06 | La verificación posterior al cambio pasa: el servicio responde a pedidos funcionales. **Prometheus deja de scrapear `otp-sms`.** Ninguna alerta: no hay datos que evaluar. |
| 14:06 → 18:15 | Los paneles de `otp-sms` en Grafana quedan en blanco. Nadie los está mirando. |
| 16:15 | Arranca una campaña de marketing con login obligatorio. El volumen de OTP pasa de ~40 a ~80 por minuto. |
| 16:20 | **Inicio del impacto.** El proveedor de SMS empieza a limitar los envíos por encima del caudal contratado (~52 por minuto). El 35 % de los códigos no se entrega. |
| 16:20 → 17:02 | Las alertas de burn rate del SLO de OTP **no disparan**: sin métricas, el SLI da "sin datos" y la condición nunca se cumple. |
| 16:48 | Soporte nota un aumento de tickets "no me llega el código". Lo trata como un problema de operadoras móviles, que es la causa habitual. |
| 17:02 | **Detección.** Soporte escala al SRE de guardia: 140 tickets en 40 minutos, todas las operadoras. |
| 17:05 | El SRE de guardia abre el dashboard de OTP: **paneles vacíos desde las 14:06.** |
| 17:08 | **Se declara el incidente P2.** War Room con SRE, Incident Manager e Identidad. |
| 17:14 | Los logs de `otp-sms` muestran respuestas `429 Too Many Requests` del proveedor desde las 16:20. |
| 17:20 | Se identifica la campaña como origen del aumento de volumen. |
| 17:31 | **Mitigación.** Se ejecuta el failover al proveedor de SMS secundario, según el runbook existente. |
| 17:40 | **Recuperación total.** Tasa de entrega en 99,6 %. |
| 17:45 | En paralelo: el SRE de guardia revisa los targets de Prometheus. `otp-sms` figura `down` desde las 14:06 con `context deadline exceeded`. |
| 18:15 | Se agrega a la `NetworkPolicy` el acceso desde `monitoring`. Vuelven las métricas. Fin del período sin monitoreo. |

## 4. Causa raíz

Este incidente tiene dos causas, y el postmortem se centra en la segunda:

- **Lo que falló:** el volumen de envíos superó el caudal contratado con el proveedor de SMS.
- **Por qué no nos enteramos:** el sistema de monitoreo estaba ciego, y estar ciego no alertaba.

La primera es un problema de capacidad que se resolvió con un procedimiento
existente. La segunda es la que convirtió una degradación de 10 minutos en una
de 80.

### 5 porqués (sobre la detección)

1. **¿Por qué no disparó ninguna alerta?** Porque las alertas del SLO de OTP
   evalúan la fracción de códigos no entregados, y desde las 14:06 no había
   métricas: el SLI daba "sin datos", no "35 % de fallas".
2. **¿Por qué no había métricas?** Porque la `NetworkPolicy` aplicada a las
   14:05 bloqueó el tráfico entrante desde el namespace `monitoring` al
   puerto de métricas.
3. **¿Por qué el cambio no contempló el monitoreo?** Porque la plantilla de
   endurecimiento listaba solo el tráfico de la aplicación. El scraping de
   Prometheus es una dependencia implícita, no estaba documentada en ningún
   lado.
4. **¿Por qué la verificación posterior no lo detectó?** Porque verificaba que
   el servicio respondiera, no que siguiera siendo observable. El checklist de
   cambios no incluía "los targets de monitoreo siguen `up`".
5. **¿Por qué 4 horas sin métricas no generaron ninguna alerta?** Porque todas
   las alertas eran sobre el valor de las métricas y ninguna sobre su
   ausencia. No existía una alerta `up == 0` ni `absent()` para los servicios
   con SLO, y Grafana mostraba "sin datos" como un panel en blanco, no en rojo.

**Causa raíz:** el sistema de monitoreo tenía un modo de falla silencioso
—la ausencia de datos equivalía a la ausencia de alertas— y un cambio de red
eliminó la telemetría de un servicio crítico sin que nada lo verificara.

### Factores contribuyentes

- **La campaña no estaba en el calendario de SRE.** Un aumento de volumen
  previsible, de 2×, no se cruzó con la capacidad contratada del proveedor.
- **Soporte atribuyó los primeros reclamos a las operadoras**, que es la
  causa más frecuente de "no me llega el SMS". Sin una alerta que dijera lo
  contrario, era una conclusión razonable.
- **El caudal contratado con el proveedor no estaba monitoreado** como un
  límite: los `429` estaban en los logs, pero no se contaban como métrica.

## 5. Qué salió bien

- **Soporte escaló.** Sin monitoreo, el canal de soporte fue el único sistema de
  detección que funcionó, y funcionó.
- **El runbook de failover al proveedor secundario existía y estaba
  actualizado.** La mitigación, una vez decidida, tardó 9 minutos.
- **Los logs llegaban por otro camino** (el agente de logs no pasa por la
  `NetworkPolicy`): con ellos se encontraron los `429` en 6 minutos.
- El War Room separó las dos causas a tiempo: primero se mitigó el impacto,
  después se arregló el monitoreo, sin mezclar los dos frentes.

## 6. Qué salió mal

- **4 horas y 10 minutos sin observar un servicio crítico**, y nadie lo supo.
- **42 minutos de impacto antes de la detección**, contra los ~5 que habría
  tardado la alerta de burn rate con métricas.
- **El cambio de red se dio por bueno con una verificación funcional.** La
  observabilidad no era parte de la definición de "el cambio salió bien".
- Un panel en blanco se ve como un panel tranquilo.

## 7. Dónde tuvimos suerte

- **La falla fue parcial (35 %).** Con un 100 % de códigos sin entregar, nadie
  habría podido iniciar sesión, y el mismo tiempo de detección habría sido un
  P1 con impacto total durante 42 minutos.
- **El contrato con el proveedor secundario estaba activo.** Se había evaluado
  darlo de baja por costos el trimestre anterior.

## 8. Acciones

| # | Acción | Tipo | Responsable | Fecha | Estado |
|---|---|---|---|---|---|
| 1 | Alerta `up == 0` o `absent(up)` durante 1 minuto, con severidad page, para todo servicio con SLO | Detectar | SRE | 2026-09-03 | Cerrada |
| 2 | Paneles de SLO en Grafana: "sin datos" se muestra en rojo con el texto "SIN MÉTRICAS", nunca en blanco | Detectar | SRE | 2026-09-03 | Cerrada |
| 3 | La plantilla de `NetworkPolicy` incluye el ingreso desde `monitoring` al puerto de métricas | Prevenir | Seguridad + Plataforma | 2026-09-10 | Cerrada |
| 4 | Test en el CI de manifiestos: toda `NetworkPolicy` de un namespace con `ServiceMonitor` debe permitir el scraping | Prevenir | Plataforma | 2026-09-30 | En curso |
| 5 | El checklist post-cambio incluye "los targets de monitoreo del servicio siguen `up`" | Prevenir | Gestión de cambios | 2026-09-10 | Cerrada |
| 6 | Métrica y alerta sobre las respuestas `429` del proveedor de SMS: más del 1 % durante 5 minutos | Detectar | Identidad | 2026-09-17 | Abierta |
| 7 | Failover automático al proveedor secundario si la tasa de entrega cae por debajo del 95 % durante 3 minutos | Mitigar | Identidad | 2026-10-31 | Abierta |
| 8 | Las campañas con login obligatorio se cargan en el calendario de capacidad de SRE con 7 días de anticipación | Prevenir | Marketing + SRE | 2026-09-17 | Cerrada |
| 9 | Runbook [servicio sin métricas](../../runbooks/es/servicio-sin-metricas.md) | Mitigar | SRE | 2026-09-03 | Cerrada |

## 9. Lecciones

- **Un sistema de alertas tiene que alertar también sobre sí mismo.** Las
  alertas sobre el valor de una métrica asumen que la métrica existe. Cuando
  no existe, el silencio se lee como "todo bien", y es la peor lectura posible.
- **Un panel en blanco se ve igual que un panel tranquilo.** En un dashboard,
  la ausencia de datos tiene que ser la cosa más visible de la pantalla.
- **"El cambio salió bien" incluye "seguimos viendo el servicio".** Una
  verificación que solo prueba el camino funcional deja afuera la mitad del
  sistema.

## Anexos

- Runbooks usados: failover de proveedor de SMS (interno) y, creado a partir de
  este incidente, [servicio sin métricas](../../runbooks/es/servicio-sin-metricas.md)
- La alerta de la acción 1 está implementada y con tests en el
  [sre-slo-lab](https://github.com/seamnex/sre-slo-lab) como `SLOSinDatos`.
- Estado del target que confirmó el diagnóstico:

  ```console
  $ curl -s localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="otp-sms") | {health, lastError}'
  {
    "health": "down",
    "lastError": "Get \"http://10.42.3.17:9102/metrics\": context deadline exceeded"
  }
  ```
