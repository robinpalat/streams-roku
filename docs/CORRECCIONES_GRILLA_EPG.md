# Correcciones funcionales de la grilla EPG

Proyecto: `streams-roku`  
Fecha: 2026-11-21  
Roku de referencia: Express 3960RW, Roku OS 15.3.4  
Alcance: reproducción desde la grilla y filtrado de canales sin programación.

No se realizaron commits ni publicación externa.

## 1. Resumen

Se corrigieron dos defectos independientes:

1. **OK en la grilla no iniciaba reproducción.** La grilla solo refrescaba el
   detalle; no emitía ningún evento hacia `MainScene` y no se invocaba
   `PlayChannel()`.
2. **La grilla mostraba todos los canales**, incluidos los que no tenían ningún
   programa en la ventana visible.

Ambas correcciones se hicieron en la capa de presentación/coordinación. No se
creó un segundo reproductor ni se modificó `PlayChannel`, `StartPlayback`, `Zap`,
`m.current`, `m.playingUrl`, `m.video` o `content.url`.

## 2. Causa demostrada de A

### Antes

El manejador de OK de `EpgGrid` era equivalente a:

```brightscript
else if key = "play" or key = "OK" then
    RenderDetail(NowSeconds())
    return true
```

No existía un campo de solicitud de reproducción, no se comprobaba si el
programa era actual, no se obtenía la URL del canal y `MainScene` no observaba
ningún evento de la grilla. Por tanto, OK **solo actualizaba la información**;
nunca llamaba al mecanismo de reproducción existente.

El fallo no era de `PlayChannel` ni del stream: la grilla nunca enviaba la
selección.

### Después

- `EpgGrid` expone `playRequest` (assocarray) y `detailNote`.
- OK comprueba `EpgProgramIsCurrent(programs, index, now)`.
- Si el programa es actual y el canal tiene URL, emite:

```brightscript
m.top.playRequest = { url: ch.url, name: ch.name, tvgId: ch.tvgId }
```

- `MainScene.onGuidePlayRequest()` recibe el evento, busca el canal original por
  URL (y `tvgId` único como respaldo), oculta la grilla y llama a
  `PlayChannel(ch)`.
- La URL es siempre `ch.url` de la lista M3U/canal original; nunca se deriva de
  EPG.
- Programa futuro: solo muestra detalles.
- Canal sin URL: “No se puede sintonizar: URL no disponible”.
- `EpgGrid` no contiene llamadas a `PlayChannel` ni `StartPlayback`; no existe
  un segundo mecanismo.

## 3. Causa y corrección de B

### Antes

`RenderGrid()` recorría directamente `m.top.channels`. La grilla pintaba todos
los canales, incluidos los que no tenían programas en la ventana de 4 h.

### Después

Se construye una lista derivada `m.visibleChannels`:

- se recorre la lista original en orden;
- se conserva `{channel, originalIndex}`;
- solo se añade si `EpgProgramsOverlap(programs, windowStart, windowEnd)` es
  verdadero;
- la misma ventana usada por el render (`m.windowStart` y `WindowEnd()`) es la
  usada por el filtro;
- `m.top.channels` (playlist/favoritos/fuentes) no se modifica.

`EpgProgramsOverlap` considera un programa si tiene título y solapa la ventana.
Si no tiene `stop`, usa el `start` del siguiente programa como límite visual; si
tampoco existe siguiente, usa el final de la ventana. No inventa una duración ni
un `stop` para la EPG.

Navegación:

- Up/Down recorre exclusivamente `m.visibleChannels`.
- Left/Right cambia de programa o de ventana temporal y reconstruye la lista
  visible con la nueva ventana.
- La selección se preserva por `tvgId`/URL (`selectedChannelKey`).
- Si el canal seleccionado desaparece, se elige el índice visible más cercano a
  su índice original (`NearestVisibleIndex`).
- Si no queda ningún canal visible, se muestra:
  “No hay canales con programación en esta ventana”.
- Al actualizar la EPG, `BuildVisibleChannels()` se ejecuta de nuevo; un canal
  que gana programación entra y uno que la pierde sale automáticamente.

Orden, favoritos, zapping, fuentes M3U y asociación `tvg-id` se conservan.

## 4. Archivos modificados

- `components/EpgGrid.xml`: campo `playRequest`, etiqueta `detailNote`.
- `components/EpgGrid.brs`: filtro visible, selección, OK/reproducción,
  actualización dinámica, estados vacíos.
- `components/MainScene.brs`: observa `playRequest`, busca el canal original y
  reutiliza `PlayChannel`; no cambia el flujo de reproducción.
- `source/epg.brs`: helpers puros `EpgProgramIsCurrent` y
  `EpgProgramsOverlap`.
- `manifest`: `build_version=18`.
- Pruebas: `pipeline/tests/test_grid_corrections.py`,
  `tests/brs/m3u_update_test.brs`.
- Documentación: este archivo.

`PlayChannel`, `StartPlayback`, `Zap`, `ZapList`, subtítulos, favoritos y
navegación existente no fueron reescritos.

## 5. Pruebas ejecutadas

| Prueba | Resultado |
|---|---|
| Python pipeline + static grid | 63 aprobadas, 0 fallidas |
| BrightScript puro (`brs`) | 62 aserciones, 0 fallidas, 6 pendientes |
| BrighterScript compile | 0 errores |
| Paquete Roku | 29 archivos, 2.031.727 bytes |
| Hash del paquete | `22c4345440d37921586078dfb519780426500d764a5666969d2f29d5da830e0e` |
| Servidor EPG 8001 | active; health/smoke OK |
| Puerto 8000 | intacto |

Pruebas nuevas relevantes:

- programa actual: `EpgProgramIsCurrent` verdadero;
- programa futuro: falso;
- programa sin `stop`: actual desde `start` hasta siguiente;
- solape de programa con ventana y programa fuera de ventana;
- `playRequest` usa `ch.url`;
- `EpgGrid` no invoca `PlayChannel`/`StartPlayback`;
- `MainScene` sí observa `playRequest` y llama a `PlayChannel`;
- filtro por `EpgProgramsOverlap` y orden original;
- navegación sobre `visibleChannels`;
- preservación de selección/vecino más cercano;
- estado sin canales visibles.

No se ejecutó el binario nuevo en Roku físico después de esta corrección. Las
pruebas de navegación/visuales/reproducción siguen pendientes de validación
física.

## 6. Comportamiento anterior y corregido

| Caso | Antes | Después |
|---|---|---|
| OK en programa actual | Solo detalle | Reproduce el canal actual |
| OK en programa futuro | Solo detalle | Detalle; no reproduce |
| Canal sin URL | Sin acción | Aviso “URL no disponible” |
| Canal sin programas en ventana | Aparecía | Se excluye de la grilla |
| Canal sin programas en todo el EPG | Aparecía | Se excluye de la grilla |
| Actualización EPG | Lista fija | Recalcula canales visibles |
| Selección al cambiar ventana | Podía quedar fuera | Se preserva o pasa al vecino más cercano |
| Lista vacía | Filas vacías | Estado vacío comprensible |

## 7. Criterio exacto de filtrado

Un canal se incluye en `m.visibleChannels` si y solo si:

1. el canal tiene un `epgId` resoluble por `CatalogEpgIdForItem()`;
2. existe una entrada de canal en `m.epg`;
3. al menos un programa de esa entrada tiene `start` y título;
4. el programa solapa la ventana `[m.windowStart, WindowEnd()]`:
   `programStart < windowEnd` y `programVisualEnd > windowStart`;
5. si falta `stop`, el final visual es el `start` del siguiente programa o,
   si no hay siguiente, el final de la ventana.

No se usa una ventana distinta para el filtro y el render.

## 8. Limitaciones pendientes

- Validación física del nuevo paquete en Roku: OK actual, futuro, canal sin URL,
  navegación y actualización EPG.
- La grilla se reconstruye por ventana visible (8 canales × 4 h); el rendimiento
  real en Roku Express debe medirse.
- La cobertura EPG real sigue siendo 17/51; los canales sin datos no aparecen en
  la grilla aunque existan en la playlist.
- No se ha implementado una grilla de varios días.
- La EPG de canales sin `stop` se representa hasta el siguiente programa/ventana;
  no se calcula progreso sin `stop`.
- El paquete debe reinstalarse mediante el instalador de desarrollo del Roku.
