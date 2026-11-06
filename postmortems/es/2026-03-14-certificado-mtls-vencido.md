# Postmortem: pagos con tarjeta rechazados durante 2 h 38 min

**Español** · [English](../en/2026-03-14-expired-mtls-certificate.md)

> **Incidente simulado.** Pagoya y todo lo que describe este documento son
> ficticios: es un ejercicio de redacción de postmortems, no un incidente real.
> Ver el [aviso del repositorio](../../README.md#aviso).

| | |
|---|---|
| **ID** | INC-2026-007 |
| **Severidad** | P1 |
| **Estado** | Cerrado |
| **Fecha del incidente** | 2026-03-14 (sábado) |
| **Duración del impacto** | 2 h 38 min (03:00 → 05:38) |
| **Tiempo de detección (MTTD)** | 7 min |
| **Tiempo de mitigación** | 2 h 31 min |
| **Servicios afectados** | `pagos-gateway` → procesador de tarjetas externo |
| **Incident Manager** | Incident Manager de guardia |
| **Autoría del documento** | Incident Manager, SRE de guardia |
| **Revisado por** | Líder técnico de Pagos, Seguridad — 2026-03-18 |

## 1. Resumen ejecutivo

Entre las 03:00 y las 05:38 del sábado 14 de marzo, **el 100 % de los pagos con
tarjeta fallaron**: 3.140 transacciones de 2.287 usuarios. Las transferencias
entre billeteras no se vieron afectadas. La causa fue el vencimiento del
certificado de cliente que Pagoya usa para autenticarse ante el procesador de
tarjetas (mTLS). Un proceso automático debía renovarlo, pero venía fallando en
silencio desde hacía 53 días. Para que no se repita vamos a monitorear el
vencimiento de **todos** los certificados, incluidos los internos, y a alertar
cuando un proceso de renovación deja de completarse.

## 2. Impacto

| Dimensión | Valor | Fuente |
|---|---|---|
| Usuarios afectados | 2.287 | Usuarios únicos con al menos un pago rechazado |
| Pagos con tarjeta fallidos | 3.140 (100 % del período) | Logs de `pagos-gateway`, código `502` |
| Pagos reintentados con éxito después de la recuperación | 1.912 (61 %) | Cruce por usuario y comercio, hasta 24 h después |
| Error budget consumido | **15 %** del budget mensual del SLO de pagos con tarjeta (99,5 %) | 3.140 fallas / 21.000 permitidas en 30 días |
| Impacto económico estimado | Comisiones de 1.228 pagos no recuperados | Finanzas, sobre el ticket promedio |
| SLA con comercios | Sin incumplimiento: el SLA es mensual y quedó en 99,93 % | Reporte de SLA de marzo |

## 3. Línea de tiempo

Todas las horas en UTC-3.

| Hora | Evento |
|---|---|
| 20/01 | Seguridad rota el token de la API del procesador como parte de la rotación trimestral. El job de renovación del certificado sigue usando el token anterior. |
| 21/01 → 13/03 | El job de renovación corre todas las noches y falla con `401 Unauthorized`. **53 fallas seguidas, ninguna alerta.** |
| 14/03 03:00 | **Inicio del impacto.** Vence el certificado de cliente mTLS. El procesador rechaza el handshake y `pagos-gateway` devuelve `502` a cada pago con tarjeta. |
| 03:07 | **Detección.** Dispara `SLOQuemaRapida` del SLO de pagos con tarjeta (burn rate 200×). Page al SRE de guardia. |
| 03:12 | El SRE de guardia confirma en el dashboard: 100 % de errores en pagos con tarjeta, transferencias normales. |
| 03:15 | **Se declara el incidente P1** y se abre el War Room. Se convoca al Incident Manager. |
| 03:18 | Primera hipótesis: caída del procesador. Los logs muestran `remote error: tls: handshake failure`, que es consistente con un problema del lado del procesador. |
| 03:30 | Primera comunicación en la página de estado: "Pagos con tarjeta con fallas. Las transferencias funcionan con normalidad." |
| 03:35 | La página de estado del procesador está en verde. Se abre un caso de prioridad crítica con el procesador. |
| 03:46 | El SRE de guardia revisa el certificado de cliente con `openssl x509 -enddate`: **venció a las 03:00.** Se descarta la hipótesis del procesador (28 min después de formularla). |
| 03:52 | Se intenta correr el job de renovación a mano: falla con `401`. Se identifica el token rotado en enero. |
| 04:05 | Con el token vigente, el job genera el CSR, pero **la firma del certificado la hace el procesador**: no se puede completar desde Pagoya. |
| 04:10 | El procesador confirma por teléfono el vencimiento y escala la firma de emergencia a su equipo de guardia. |
| 05:20 | El procesador entrega el certificado firmado. |
| 05:32 | **Mitigación.** Se actualiza el secret en el cluster y se reinician los pods de `pagos-gateway` de a uno. |
| 05:38 | **Recuperación total.** Tasa de éxito de pagos con tarjeta en 99,8 %, igual que la línea de base. |
| 06:10 | Se cierra el War Room. Comunicación de resolución en la página de estado. |

## 4. Causa raíz

### 5 porqués

1. **¿Por qué fallaron los pagos con tarjeta?** Porque el procesador rechazó el
   handshake mTLS: el certificado de cliente de Pagoya venció a las 03:00.
2. **¿Por qué venció el certificado?** Porque el job que lo renueva 7 días
   antes del vencimiento no lo renovó.
3. **¿Por qué no lo renovó?** Porque se autentica contra la API del procesador
   con un token que Seguridad rotó el 20 de enero, y el job seguía con el
   anterior. Falló con `401` las 53 noches siguientes.
4. **¿Por qué nadie se enteró de 53 fallas?** Porque el job registraba el error
   en un log que nadie consultaba y terminaba con código 0: para el
   orquestador, cada corrida fue exitosa. No había alerta sobre el resultado
   del job ni sobre la fecha de vencimiento del certificado.
5. **¿Por qué no había alerta de vencimiento?** Porque el inventario de
   certificados monitoreados solo incluía los TLS públicos (los del sitio y la
   API). El certificado de cliente mTLS vivía como un secret del cluster, fuera
   del inventario, y no tenía un equipo responsable definido: Pagos asumía que
   era de Plataforma, y Plataforma, que era de Pagos.

**Causa raíz:** la renovación de una credencial crítica dependía de un proceso
que podía fallar en silencio, sin monitoreo de su ejecución ni del resultado
que importa (la fecha de vencimiento), y la credencial no figuraba en ningún
inventario con un responsable asignado.

### Factores contribuyentes

- **La rotación del token no listaba a sus consumidores.** El procedimiento de
  rotación de Seguridad actualizó las aplicaciones conocidas; el job de
  renovación no estaba en la lista.
- **La firma depende de un tercero.** Aun con el diagnóstico correcto, la
  recuperación no podía bajar del tiempo de respuesta del procesador (1 h 10 min).
- **El mensaje de error era ambiguo.** `tls: handshake failure` no dice qué
  lado falla. La hipótesis "se cayó el procesador" era razonable con esa
  evidencia y costó 28 minutos descartarla.
- **No había runbook** para fallas de certificados.

## 5. Qué salió bien

- **La alerta de SLO detectó el impacto en 7 minutos**, a las 3 de la mañana
  de un sábado, sin depender de que un cliente llamara.
- El dashboard separaba pagos con tarjeta de transferencias: en 5 minutos se
  supo que el impacto era acotado, y la primera comunicación lo dijo con
  precisión.
- El caso crítico con el procesador se abrió en paralelo al diagnóstico, no
  después. Cuando se confirmó la causa, el procesador ya estaba en contacto.
- El reinicio de los pods fue de a uno: los pocos pagos que llegaron durante
  la mitigación no sumaron errores nuevos.

## 6. Qué salió mal

- **Se sostuvo una hipótesis 28 minutos sin buscar evidencia en contra.** La
  verificación que la descartó —leer la fecha del certificado— tardaba 30
  segundos.
- **Nadie sabía quién era responsable del certificado.** La primera media hora
  de diagnóstico fue también una búsqueda del dueño.
- **La renovación de emergencia no tenía procedimiento acordado** con el
  procesador. Se resolvió por teléfono y por buena voluntad.
- **53 fallas seguidas del job sin una sola alerta.** El sistema tuvo casi dos
  meses de margen para avisar y no avisó nunca.

## 7. Dónde tuvimos suerte

- **Fue a las 3 de la mañana de un sábado.** El volumen de pagos con tarjeta
  a esa hora es aproximadamente 1/12 del de un mediodía hábil. El mismo
  incidente un martes a las 12:00 habría afectado a unos 37.000 pagos y
  habría agotado el error budget del mes entero en alrededor de una hora y media.
- **El equipo de guardia del procesador atendió el teléfono** y aceptó firmar
  fuera de su proceso habitual. No había nada acordado que lo garantizara.

## 8. Acciones

| # | Acción | Tipo | Responsable | Fecha | Estado |
|---|---|---|---|---|---|
| 1 | Alertar el vencimiento de **todos** los certificados (públicos, mTLS e internos) a 30, 14 y 7 días | Detectar | SRE / Plataforma | 2026-03-28 | Cerrada |
| 2 | El job de renovación termina con código distinto de 0 ante cualquier error, y una alerta tipo *dead man's switch* avisa si no hubo una corrida exitosa en 48 h | Detectar | Plataforma | 2026-03-28 | Cerrada |
| 3 | Inventario versionado de certificados y credenciales con equipo responsable, fecha de vencimiento y procedimiento de renovación | Prevenir | Seguridad + Pagos | 2026-04-15 | En curso |
| 4 | Renovar 30 días antes del vencimiento en lugar de 7 | Prevenir | Pagos | 2026-04-01 | Cerrada |
| 5 | El procedimiento de rotación de tokens exige listar sus consumidores y verificar cada uno después de rotar | Prevenir | Seguridad | 2026-04-15 | En curso |
| 6 | Acordar con el procesador un procedimiento de firma de emergencia con tiempo de respuesta comprometido | Mitigar | Gerencia de Partners | 2026-04-30 | Abierta |
| 7 | Runbook [certificado TLS por vencer o vencido](../../runbooks/es/certificado-tls-por-vencer.md) | Mitigar | SRE | 2026-03-21 | Cerrada |

## 9. Lecciones

- **Un proceso automático que puede fallar en silencio es una bomba de tiempo
  con la mecha escondida.** No alcanza con automatizar la renovación: hay que
  monitorear el *resultado* (la fecha de vencimiento), no solo la ejecución.
- **Toda credencial necesita un dueño.** "Es de todos" es "no es de nadie"
  medido en minutos de War Room.
- **El primer paso del diagnóstico es lo más barato de verificar, no lo más
  probable.** Leer la fecha de un certificado son 30 segundos; descartar una
  caída del procesador fueron 28 minutos.

## Anexos

- Runbook creado a partir de este incidente: [certificado TLS por vencer o vencido](../../runbooks/es/certificado-tls-por-vencer.md)
- Verificación que confirmó la causa:

  ```bash
  kubectl get secret pagos-procesador-mtls -n pagos -o jsonpath='{.data.tls\.crt}' \
    | base64 -d | openssl x509 -noout -enddate
  # notAfter=Mar 14 06:00:00 2026 GMT     (03:00 UTC-3)
  ```
