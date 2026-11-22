# Rediseño visual de la grilla EPG

Proyecto: `streams-roku`  
Fecha: 2026-11-21  
Dispositivo objetivo: Roku Express 3960RW  
Alcance: presentación visual de `EpgGrid`. Sin cambios funcionales.

No se realizaron commits ni publicación externa.

> Nota de vigencia: la paleta, tipografía y jerarquía de este documento siguen
> vigentes. La altura de filas, el número de filas visibles y el panel inferior
> fueron ajustados posteriormente por legibilidad; la geometría vigente está en
> `docs/AJUSTE_GEOMETRICO_EPG.md` (6 filas de 74 px, panel de 120 px).

## 1. Criterio de diseño

La intervención se limitó a la capa visual:

- reducir el peso de los bloques y de los contrastes;
- sustituir los acentos azul/verde intensos por tonos petróleo apagados;
- ordenar la jerarquía tipográfica;
- dar aire a las filas y a las celdas;
- separar el título y la descripción del panel inferior, que antes podían
  solaparse;
- mantener la lectura cómoda a distancia de salón.

No se añadieron dependencias, imágenes decorativas ni transparencias. No se
modificó la lógica de EPG, filtrado, asociación de programas, navegación ni
reproducción.

## 2. Paleta

Fondo azul petróleo muy oscuro, superficies por variación tonal y un único
acento turquesa apagado.

| Uso | Color |
|---|---|
| Fondo general | `0x0A1419FF` |
| Cabecera | `0x0C1A1FFF` |
| Fila par | `0x0D1B20FF` |
| Fila impar | `0x0C181DFF` |
| Fila seleccionada | `0x10252BFF` |
| Columna de canal | `0x0F2026FF` |
| Columna de canal seleccionada | `0x173039FF` |
| Programa futuro | `0x11252BFF` |
| Programa actual | `0x1E4A47FF` |
| Programa pasado | `0x0F1D22FF` |
| Programa seleccionado | `0x2A5C66FF` |
| Acento de selección | `0x8BCFC5FF` |
| Línea de hora actual | `0xB97C6EFF` |
| Texto principal | `0xEAF3F2FF` / `0xF0F7F6FF` |
| Texto secundario | `0x7E9699FF` / `0x8AA2A4FF` |
| Texto terciario | `0x6E8588FF` / `0x7F9699FF` |
| Separadores | `0x173037FF` / `0x1A3036FF` |

La selección usa un turquesa azulado contenido, no un verde fluorescente. El
programa actual usa un verde petróleo más luminoso que los futuros, pero menos
saturado que la selección. El pasado queda deliberadamente apagado.

No se usaron transparencias: todos los colores son RGBA opacos para asegurar una
representación estable y evitar coste de composición.

## 3. Tipografía

Se utiliza la escala del sistema Roku, sin fuentes externas.

| Elemento | Fuente | Tratamiento |
|---|---|---|
| «Guía de programación» | `font:MediumSystemFont` | Título principal |
| Intervalo temporal | `font:SmallSystemFont` | Secundario, alineado a la derecha |
| «CANAL» y horas | `font:SmallestSystemFont` | Terciario, bajo contraste |
| Nombre de canal | `font:SmallSystemFont` | Intermedio, una línea |
| Título de programa en celda | `font:SmallSystemFont` | Compacto, una línea |
| Horario en celda | `font:SmallestSystemFont` | Menor y más apagado |
| Título en panel | `font:MediumSystemFont` | Mayor jerarquía |
| Canal en panel | `font:SmallSystemFont` | Referencia secundaria |
| Horario en panel | `font:SmallSystemFont` | Línea compacta |
| Descripción | `font:SmallSystemFont` | Texto secundario |
| Nota/ayuda | `font:SmallestSystemFont` | Terciario |

Los títulos de celda ya no usan el tamaño por defecto, mayor y más pesado. Se
añadió truncado manual con elipsis (`Ellipsize`) para nombre de canal, título de
programa y horario de celda. Los textos no se superponen: título y horario tienen
líneas separadas dentro de la celda.

El panel inferior separa en dos columnas:

- izquierda: canal, título, horario y nota;
- derecha: descripción.

Esto corrige el solapamiento del diseño anterior, donde el título ancho y la
descripción compartían zona vertical.

## 4. Geometría

Se conservaron estrictamente las dimensiones temporales y de navegación:

| Constante | Valor |
|---|---|
| `m.timeX` | `200` |
| `m.timeW` | `1040` |
| `m.rowTop` | `100` |
| `m.rowH` | `56` |
| `m.visibleRows` | `8` |
| `m.windowMinutes` | `240` |

La fórmula de posición temporal no cambió:

```brightscript
x = m.timeX + Int(((ps - m.windowStart) / 60 / m.windowMinutes) * m.timeW)
```

Tampoco cambió `WindowEnd()`, el filtrado por solape, el número de filas
visibles, el desplazamiento temporal ni las teclas.

Ajustes visuales:

- filas de 54 px de superficie dentro del paso de 56 px, con separación fina;
- columna de canal de 180 px, logo de 46 × 30 px centrado;
- divisor vertical de 1 px en `x=199`;
- celdas de programa con 5 px de margen vertical y 3 px de separación;
- título y horario en líneas independientes;
- cabecera temporal de 82 px de alto, horas a `y=58` y líneas desde `y=100`;
- línea de hora actual de 1 px, etiqueta «Ahora» de 16 px;
- panel inferior de 112 px de alto, desde `y=554` hasta `y=666`;
- ayuda inferior a `y=682`.

La altura del panel se redujo de 118 a 112 px y se eliminó la superposición entre
título y descripción.

## 5. Estados

| Estado | Fondo | Texto | Nota |
|---|---|---|---|
| Futuro | `0x11252BFF` | Claro apagado | Base normal |
| Actual | `0x1E4A47FF` | Claro verdoso | Más luminoso que futuro |
| Pasado | `0x0F1D22FF` | Gris petróleo | Menor contraste |
| Seleccionado | `0x2A5C66FF` | Casi blanco | Barra izquierda turquesa |

El foco de navegación se representa con el bloque seleccionado, la barra
izquierda y la celda de canal resaltada. El estado «actual» se representa por el
tono del bloque, no por el foco. No se usan colores fluorescentes.

## 6. Cabecera y navegación

- Título «Guía de programación» con acento fino de 30 × 2 px.
- Intervalo temporal a la derecha, en tamaño menor y color secundario.
- Etiqueta «CANAL» alineada con la columna.
- Horas cada 30 min, con menor peso visual.
- Indicador «Ahora» y línea vertical fina, sin rojo intenso.
- Instrucciones inferiores discretas:
  `Up/Down canal · Left/Right programa · OK detalles · Back volver`.

Las indicaciones y el comportamiento de Up/Down, Left/Right, OK y Back se
mantienen.

## 7. Panel inferior

- El nombre del canal es la referencia secundaria.
- El título del programa tiene la mayor jerarquía.
- El horario ocupa una línea compacta.
- La descripción usa tipografía menor y ancho de lectura limitado.
- El mensaje de programa futuro se conserva.
- La nota de reproducción cambia de color según el estado, sin cambiar su texto
  ni su lógica.
- Los márgenes internos son consistentes: 36 px a la izquierda, 450 px para la
  descripción, 1180 px de ancho para la nota.

## 8. Archivos modificados

- `components/EpgGrid.xml`: fondo, cabecera, tipografías, paleta, panel inferior,
  ayuda, geometría visual.
- `components/EpgGrid.brs`: colores/estados, cabecera temporal, línea de hora,
  filas, celdas, panel, truncado con elipsis.
- `pipeline/tests/test_visual_epg.py`: pruebas estáticas de geometría temporal,
  escala tipográfica, paleta, panel y elipsis.
- `manifest`: `build_version=18`.
- `docs/REDISENO_VISUAL_EPG.md`: este informe.

No se modificaron `PlayChannel`, `StartPlayback`, `Zap`, `BuildVisibleChannels`,
`EpgProgramsOverlap`, `MainScene` ni el flujo de `playRequest`.

## 9. Validación

| Prueba | Resultado |
|---|---|
| Python pipeline | 63 pruebas, 0 fallidas |
| BrightScript puro | 62 aserciones, 0 fallidas, 6 pendientes |
| BrighterScript | 0 errores |
| Paquete | 29 archivos, 2.031.727 bytes |
| SHA-256 | `22c4345440d37921586078dfb519780426500d764a5666969d2f29d5da830e0e` |

Se comprobó estáticamente que:

- `m.timeX`, `m.timeW`, `m.rowTop`, `m.rowH`, `m.visibleRows` y
  `m.windowMinutes` no cambiaron;
- la fórmula de posición temporal y `WindowEnd()` siguen intactas;
- el filtrado por solape y la navegación no se tocaron;
- no se añadieron llamadas a reproducción en la grilla;
- el panel inferior cabe entre la grilla y la ayuda.

## 10. Limitaciones

- No se ejecutó el paquete nuevo en el Roku físico; la validación visual final
  sigue pendiente.
- La representación exacta de las fuentes del sistema puede variar ligeramente
  respecto a las estimaciones de ancho usadas para la elipsis.
- No se añadió una vista de varios días ni nuevas funciones.
- La cobertura EPG y el filtrado de canales con programación no se modificaron.
