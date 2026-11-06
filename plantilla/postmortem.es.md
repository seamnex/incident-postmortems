# Postmortem: [título corto que describa el impacto, no la causa]

**Español** · [English](postmortem.en.md)

<!--
Plantilla de postmortem sin culpables (blameless).

Reglas de escritura:
- Se describen sistemas, decisiones y señales, nunca personas. "El deploy
  se aprobó sin el chequeo X" y no "Juan aprobó el deploy sin revisar".
  Si alguien tomó una mala decisión con la información que tenía, el
  problema es la información que tenía.
- Toda afirmación del impacto lleva un número y de dónde salió.
- La causa raíz se escribe después de la línea de tiempo, no antes. Escribir
  primero la causa tienta a ordenar los hechos para que la confirmen.
- Las acciones tienen responsable (un rol o equipo) y fecha. Una acción sin
  fecha es un deseo.
-->

| | |
|---|---|
| **ID** | INC-AAAA-NNN |
| **Severidad** | P1 / P2 / P3 |
| **Estado** | Borrador · En revisión · Cerrado |
| **Fecha del incidente** | AAAA-MM-DD |
| **Duración del impacto** | HH:MM (de la primera señal de impacto a la recuperación total) |
| **Tiempo de detección (MTTD)** | HH:MM (del inicio del impacto a la primera alerta o aviso) |
| **Tiempo de mitigación** | HH:MM (de la detección al fin del impacto) |
| **Servicios afectados** | |
| **Incident Manager** | rol |
| **Autoría del documento** | rol(es) |
| **Revisado por** | rol(es) — fecha |

## 1. Resumen ejecutivo

<!--
Tres a cinco oraciones que entienda alguien que no es técnico y que no va a
leer el resto: qué pasó, a quién afectó, cuánto duró, por qué pasó (en una
línea) y qué se va a hacer para que no se repita.
-->

## 2. Impacto

<!--
Cuantificado. Usuarios, transacciones, dinero, SLO.
-->

| Dimensión | Valor | Fuente |
|---|---|---|
| Usuarios afectados | | |
| Transacciones fallidas o demoradas | | |
| Error budget consumido | % del budget mensual del SLO X | |
| Impacto económico estimado | | |
| Compromisos contractuales (SLA) | | |

## 3. Línea de tiempo

<!--
Zona horaria explícita. Cada entrada: qué pasó y cómo se supo. Marcar los
hitos: inicio del impacto, detección, declaración, mitigación, recuperación.
-->

Todas las horas en UTC-3.

| Hora | Evento |
|---|---|
| HH:MM | **Inicio del impacto.** |
| HH:MM | **Detección.** |
| HH:MM | Se declara el incidente (Pn) y se abre el War Room. |
| HH:MM | **Mitigación.** |
| HH:MM | **Recuperación total.** |

## 4. Causa raíz

### 5 porqués

<!--
Cada "porqué" se apoya en evidencia (log, métrica, commit, config), no en
suposiciones. Si una respuesta es "error humano", todavía no se llegó a la
causa: la pregunta siguiente es por qué el sistema permitió ese error.
-->

1. **¿Por qué ...?** Porque ...
2. **¿Por qué ...?** Porque ...
3. **¿Por qué ...?** Porque ...
4. **¿Por qué ...?** Porque ...
5. **¿Por qué ...?** Porque ...

**Causa raíz:**

### Factores contribuyentes

<!--
Lo que no causó el incidente pero lo hizo más largo, más grave o más
difícil de diagnosticar.
-->

-

## 5. Qué salió bien

-

## 6. Qué salió mal

-

## 7. Dónde tuvimos suerte

<!--
Lo que salió bien sin que nadie lo hubiera diseñado así. Es la sección más
honesta del documento y la que más acciones genera.
-->

-

## 8. Acciones

<!--
Tipo: Prevenir (que no vuelva a pasar) · Detectar (enterarnos antes) ·
Mitigar (que duela menos si pasa). Si todas son de un solo tipo, falta mirar.
-->

| # | Acción | Tipo | Responsable | Fecha | Estado |
|---|---|---|---|---|---|
| 1 | | Prevenir | | | Abierta |
| 2 | | Detectar | | | Abierta |
| 3 | | Mitigar | | | Abierta |

## 9. Lecciones

-

## Anexos

- Runbook usado:
- Dashboards:
- Hilo / canal del War Room:
