# Ajuste geométrico de la grilla EPG

Proyecto: `streams-roku`  
Fecha: 2026-11-21  
Dispositivo objetivo: Roku Express 3960RW  
Alcance: altura de filas y distribución vertical. Sin cambios de lógica.

No se realizaron commits ni publicación externa.

## 1. Problema corregido

El rediseño cromático anterior mantuvo filas de 56 px. Esa altura era insuficiente
para el nombre de canal en una sola línea y dejaba muy poco margen vertical entre
el título y el horario de cada programa.

La solución aplicada no reduce más la tipografía ni trunca más los textos:

- se pasa de **8 filas de 56 px** a **6 filas de 74 px**;
- el área útil de la grilla se mantiene prácticamente igual: 448 → 444 px;
- se aprovecha el espacio para dar dos líneas al canal y separar título/horario;
- el panel inferior crece de 112 a 120 px, en lugar de reducirse.

## 2. Distribución vertical

| Zona | Coordenadas / altura |
|---|---|
| Cabecera | `y=0..81` |
| Etiquetas horarias | `y=58..76` |
| Inicio de filas | `y=100` |
| 6 filas × 74 px | `y=100..544` |
| Línea divisoria del panel | `y=548` |
| Panel informativo | `y=550..670` (120 px) |
| Ayuda de navegación | `y=682..700` |

Cálculo del área de filas:

```text
6 filas × 74 px = 444 px
100 + 444 = 544 px
```

Quedan 4 px hasta la línea del panel y 12 px entre el panel y la ayuda. Las seis
filas aprovechan el mismo alto que antes ocupaban las ocho, sin comprimir el
panel.

La líneas verticales de la escala temporal y la línea de hora actual usan ahora
`m.visibleRows * m.rowH` (444 px), en lugar de una altura fija.

## 3. Columna de canales

- Altura de celda: 72 px dentro del paso de fila de 74 px.
- Logo: 46 × 30 px, centrado verticalmente en `y+22`.
- Nombre: `x=84`, `y+15`, ancho 106 px, alto 44 px.
- `wrap=true` para permitir dos líneas.
- `vertAlign="center"` para centrar el bloque de texto verticalmente.
- Se conserva el truncado con elipsis solo para nombres extremadamente largos
  (24 caracteres), evitando una tercera línea y el recorte inferior.

El nombre ya no queda en una única línea de 22 px ni se corta verticalmente.

## 4. Celdas de programación

Todas las celdas de una fila tienen exactamente la misma altura:

- bloque: `y+7`, alto `m.rowH - 14` = **60 px**;
- título: `y=8` dentro del bloque, alto 24 px;
- horario: `y=33` dentro del bloque, alto 18 px;
- margen interno horizontal: 8 px;
- separación entre bloques: 3 px;
- título y horario no se superponen: el título termina en 32 y el horario
  comienza en 33.

El contenido queda centrado verticalmente: 8 px arriba, 24 px de título, 1 px
de separación, 18 px de horario y 9 px abajo (total 60 px).

La proporción horizontal no cambió:

```brightscript
x = m.timeX + Int(((ps - m.windowStart) / 60 / m.windowMinutes) * m.timeW)
w = Int(((pe - ps) / 60 / m.windowMinutes) * m.timeW)
```

`m.timeX=200`, `m.timeW=1040`, `m.windowMinutes=240` y `WindowEnd()` permanecen
intactos.

## 5. Tipografía

No se redujeron tamaños respecto al rediseño anterior:

| Elemento | Fuente |
|---|---|
| Nombre de canal | `font:SmallSystemFont`, dos líneas |
| Título de programa | `font:SmallSystemFont` |
| Horario de programa | `font:SmallestSystemFont` |
| Título del panel | `font:MediumSystemFont` |
| Descripción | `font:SmallSystemFont` |
| Nota y ayuda | `font:SmallestSystemFont` |

La mejora de legibilidad viene del espacio vertical, no de reducir la letra.

## 6. Panel inferior

El panel no se redujo. Pasó de 112 a 120 px:

- fondo: `y=550`, alto 120 px;
- canal: `y=560`;
- título: `y=580`, alto 44 px;
- horario: `y=628`;
- descripción: `x=450`, `y=560`, ancho 790, alto 78 px;
- nota: `y=650`, alto 16 px.

La descripción mantiene su columna independiente y no se solapa con el título.

## 7. Navegación y lógica

No se modificó:

- Up/Down entre canales;
- Left/Right y desplazamiento temporal;
- selección visual y preservación de selección;
- filtrado por `EpgProgramsOverlap`;
- asociación de programas;
- `playRequest` ni `PlayChannel`.

Solo cambiaron constantes visuales (`m.rowH`, `m.visibleRows`), posiciones y
alturas de nodos. `m.rowOffset` y la navegación ya usaban `m.visibleRows`, por lo
que se adaptan automáticamente a seis filas.

No se añadieron nodos por fila: se reutilizan los mismos rectángulos, etiquetas y
logo, con mayores alturas.

## 8. Archivos modificados

- `components/EpgGrid.brs`: filas de 74 px, 6 visibles, nombre de canal a dos
  líneas, celdas de 60 px, título/horario separados, alturas dinámicas de líneas.
- `components/EpgGrid.xml`: panel inferior de 120 px y posiciones interiores.
- `pipeline/tests/test_visual_epg.py`: geometría de filas, distribución vertical,
  dos líneas de canal y separación título/horario.
- `pipeline/tests/test_app_config.py`: expectativa de 6 filas visibles.
- `manifest`: `build_version=18`.
- `docs/AJUSTE_GEOMETRICO_EPG.md`: este informe.

## 9. Validación

| Prueba | Resultado |
|---|---|
| Python pipeline | 63 pruebas, 0 fallidas |
| BrightScript puro | 62 aserciones, 0 fallidas, 6 pendientes |
| BrighterScript | 0 errores |
| Paquete | 29 archivos, 2.031.727 bytes |
| SHA-256 | `22c4345440d37921586078dfb519780426500d764a5666969d2f29d5da830e0e` |

Comprobaciones estáticas:

- 6 × 74 = 444 px; la grilla termina en 544 y no invade el panel;
- todas las celdas usan `m.rowH - 14` = 60 px;
- título y horario tienen intervalos verticales disjuntos;
- el nombre de canal tiene 44 px y `wrap=true`;
- logo centrado en la fila;
- panel de 120 px, no reducido;
- geometría temporal y filtrado sin cambios;
- navegación y reproducción sin cambios.

## 10. Limitaciones

- No se ejecutó el paquete nuevo en el Roku físico; la comprobación visual final
  de nombres largos y títulos extensos sigue pendiente.
- Las métricas exactas de las fuentes del sistema pueden variar ligeramente; por
  eso el nombre de canal conserva una elipsis de seguridad para casos extremos.
- No se añadieron funciones nuevas ni se alteró la EPG.
