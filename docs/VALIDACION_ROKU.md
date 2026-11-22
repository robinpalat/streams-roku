# Validación integral en Roku físico

Proyecto: `streams-roku`  
Fecha de preparación: 2026-11-21  
Alcance: auditoría estática y protocolo de pruebas. **No se modificó código.**

## 1. Resumen

La app está instalada en un Roku físico y la geometría de logos se reporta como
corregida. Esta intervención no cambia la implementación: prepara una auditoría
reproducible y una matriz de validación física. Las pruebas de este documento
están en estado **NOT TESTED** hasta que se ejecuten en el dispositivo.

## 2. Auditoría estática

### Flujo actual

- `MainScene.init()` carga fuentes/favoritos, arranca `PlaylistTask` en modo
  `load` y `MetadataTask` si la fuente tiene base de metadatos.
  `components/MainScene.brs:1-76`.
- `LoadPlaylist()` (`MainScene.brs:108`) inicia la carga cache-first.
- `onPlaylist()` (`MainScene.brs:146`) distingue `ok`, `cache`, `updated`,
  `notmodified`, `quarantine` y `error`.
- `ApplyPlaylistUpdate()` (`MainScene.brs:187`) reemplaza canales y reconcilia
  foco; no toca reproducción.
- La lista es `MarkupList` (`components/MainScene.xml:18`) con
  `ChannelItem`; el logo está en un `Poster` fijo 58×36 y `FitLogoInBox()`
  aplica contain/centrado (`components/ChannelItem.xml`, `source/logo_geometry.brs`).
- `PlayChannel()` (`MainScene.brs:468`) y `StartPlayback()` (`MainScene.brs:500`)
  conservan el contrato: `m.current`, `m.playingUrl`, `m.video`, `content.url`,
  `streamFormat`, subtítulos y reintentos.
- `Zap()`/`ZapList()` (`MainScene.brs:614-657`) y `ScheduleRetry()`
  (`MainScene.brs:659`) no fueron alterados por metadatos.
- `MetadataTask` (`components/MetadataTask.brs`) descarga `latest.json` y solo
  baja catálogo/EPG si cambia la versión o falta/está corrupta la caché.
- `PlaylistTask` (`components/PlaylistTask.brs`) implementa slots A/B, sidecars,
  ETag/Last-Modified, hash, validación, anomalías, cuarentena y backoff.

### Hallazgos y riesgos estáticos

| ID | Hallazgo | Evidencia | Impacto | Prueba |
|---|---|---|---|---|
| R-01 | `onPlaylist()` limpia `m.playlistInFlight` antes de comparar `r.id` con la fuente activa | `MainScene.brs:146-150` | Un resultado viejo puede habilitar otra comprobación mientras la nueva sigue en vuelo; posible solapamiento de tareas | D06/D07 |
| R-02 | `onMetadata()` limpia `m.metaInFlight` antes de validar `r.id`; `StartMetadata()` no arranca si la tarea vieja sigue en vuelo | `MainScene.brs:745-761` | Tras cambiar de fuente, la metadata de la nueva puede quedar sin cargar hasta el timer de 900 s | F01/F02 |
| R-03 | En actualización con reordenamiento, `m.channels` cambia pero `m.view` queda con la lista anterior hasta reabrir | `MainScene.brs:205-211` | `onItemSelected()` puede reproducir una entrada vieja/eliminada si el usuario selecciona antes de reabrir | B07 |
| R-04 | No hay logging de diagnóstico de HTTP, caché ni EPG; solo estados de UI | `PlaylistTask.brs` no usa `print`; `MainScene` tampoco | Difícil distinguir 304, error de red, cuarentena o caché corrupta desde el Roku | D05/E03 |
| R-05 | `MetaFetchText()` usa `GetToString()` síncrono sin timeout explícito | `MetadataTask.brs:191-198` | La tarea puede quedar bloqueada; no afecta al hilo de vídeo, pero retrasa metadatos | F01 |
| R-06 | Hash/validación recorre M3U de ~2,7 MB en BrightScript | `PlaylistTask`, `m3u_update.brs` | Posible latencia de comprobación en dispositivos de baja gama | D01/D02 |
| R-07 | `onMetadata()` puede reconstruir la lista al cambiar el catálogo | `MainScene.brs:766-771` | Si falla la identidad del foco, puede moverse el elemento enfocado | B07 |
| R-08 | `ChannelItem` usa `HDPOSTERURL`; las filas de Fuentes/Añadir/Directorio no asignan logo y muestran el placeholder por defecto | `MainScene.brs:319-328`, `ChannelItem.brs` | Ruido visual, no solapamiento | C01 |
| R-09 | La tarjeta EPG usa nombres/descripciones largas en 390 px | `MainScene.xml` | Texto truncado o poco legible | F03/F04 |
| R-10 | La EPG se muestra en hora local del dispositivo; no se convierte a la zona del canal | `source/epg.brs` | Expectativa distinta si el usuario viaja o compara con la web del canal | F07 |
| R-11 | El estado `ambiguous` de recuperación A/B no se muestra al usuario | `PlaylistTask.brs:172-233`; `MainScene.onPlaylist` | Recuperación silenciosa de una versión no confirmada como reciente | D08 |
| R-12 | `MetadataTask` puede mantener estado de versión nuevo con fallback de catálogo/EPG viejo si falla una descarga | `MetadataTask.brs:41-131` | Una siguiente comprobación puede tardar en reparar la caché | E04/F09 |

No se identificaron cambios en `PlayChannel`, `StartPlayback`, `Zap`,
`ZapList`, subtítulos ni `content.url` por la integración de metadatos. La
verificación física sigue siendo obligatoria.

## 3. Pruebas automatizadas existentes

Ejecutadas sin modificar el proyecto:

| Suite | Resultado |
|---|---|
| `python3 -m unittest discover -s pipeline/tests` | 63 pruebas OK |
| `tests/run_brs_tests.sh` (con `brs`) | 62 aserciones, 0 fallos, 6 pendientes |
| `bsc --create-package false --diagnostic-level error` | 0 errores |
| Paquete Roku | ~2,0 MB, 29 archivos |

Estas pruebas son estáticas/puras. No sustituyen PASS de Roku físico. Las 6
pendientes de `brs` son: reinicio/slots, pérdida total de `cachefs`, metadatos
corruptos, 304/HTTP, timeout/DNS/500 e interrupción de descarga.

## 4. Herramientas de diagnóstico

Comprobado en este entorno Linux:

- `telnet`, `nc`, `socat`, `curl` disponibles.
- No se asume `rk` CLI ni Roku Resource Monitor instalados.

Roku:

1. **IP:** `Settings > Network > About` (el nombre exacto varía por versión).
   Si ya se conoce la IP, ECP responde en el puerto 8060:
   `curl http://IP:8060/query/device-info`.
2. **Consola BrightScript:** `telnet IP 8085` (puerto oficial de consola).
   Mantener la sesión abierta. Comandos útiles: `help`, `bt`, `threads`,
   `var`, `last`, `gc`.
3. **ECP:** puerto 8060:
   - `curl http://IP:8060/query/device-info`
   - `curl http://IP:8060/query/active-app`
   - `curl http://IP:8060/query/media-player`
   - `curl -d '' http://IP:8060/keypress/Home` (requiere developer mode y
     *Control by mobile apps* habilitado; verificar antes de usar).
4. **Errores SceneGraph:** se muestran en la consola 8085, especialmente al
   arrancar/sideloadear. No hay logging propio de la app.
5. **Fallos HTTP/caché/EPG:** la app no imprime razones de `PlaylistTask` ni
   `MetadataTask`; observar el texto de estado/UI, la consola y los logs del
   servidor local. Esta es una limitación de diagnóstico, no una prueba.
6. **Memoria:** usar Roku Resource Monitor si está disponible en el dispositivo.
   No se asume su presencia; anotar modelo, OS y memoria observada.

Referencias oficiales consultadas: `developer.roku.com/dev/docs/debugging`,
`developer.roku.com/dev/docs/external-control-api`,
`developer.roku.com/dev/docs/file-system` y
`developer.roku.com/dev/docs/optimization-techniques`.

## 5. Matriz de validación física

Estados: **NOT TESTED** (inicial), PASS, FAIL, BLOCKED. No marcar PASS sin
ejecutarlo en el Roku físico. Se preparan **60 pruebas**: 45 de la matriz
original (P0: 3, A: 6, B: 7, C: 6, D: 8, E: 5, F: 10) y 15 de la ampliación
EPG automática/grilla.

### Bloque P0 — Humo y diagnóstico

| ID | Objetivo / pasos | Resultado esperado | Fallo / información | Estado |
|---|---|---|---|---|
| P0-01 | Abrir la app desde Home; esperar lista; abrir panel con Back | Lista visible, sin crash, foco en un canal | Crash, lista vacía, excepción en consola: guardar consola y device-info | NOT TESTED |
| P0-02 | Anotar IP, modelo, OS (`query/device-info`), versión de app y abrir `telnet IP 8085` | Datos y consola disponibles | No hay consola/IP: anotar BLOCKED y motivo | NOT TESTED |
| P0-03 | Abrir panel y recorrer 10 canales | Logos dentro de cajas uniformes, sin solapamiento, texto legible | Logo grande, superpuesto o fuera de fila: foto + canal + hora | NOT TESTED |

### Bloque A — Reproducción

| ID | Objetivo / pasos | Resultado esperado | Fallo / información | Estado |
|---|---|---|---|---|
| A-01 | Elegir un canal HLS y reproducir | Vídeo inicia; título muestra el canal | Error, buffering infinito, pantalla negra: canal, URL, consola, `query/media-player` | NOT TESTED |
| A-02 | Volver al panel y cambiar rápidamente entre 5–10 canales | Cambio estable, sin reinicio de escena, sin crash | Cuelgue, canal equivocado, crash: secuencia y consola | NOT TESTED |
| A-03 | Probar HLS, MP4/VOD, TS/otros formatos disponibles | Cada uno inicia o falla de forma controlada | Fallo inesperado o reinicio de app: formato, URL, consola | NOT TESTED |
| A-04 | Lanzar un stream inválido mediante ECP o reproducir un canal caído; observar 5 reintentos | Mensajes 2/4/8/16/30 s; no reinicia la app | Bucle infinito, crash, pérdida de foco: canal, consola, tiempos | NOT TESTED |
| A-05 | En un canal con subtítulos, pulsar Replay varias veces | On/off y pista cambian sin detener vídeo | Subtítulos no cambian, crash: canal y pista | NOT TESTED |
| A-06 | Reproducir; abrir panel; pulsar Replay (chequeo de lista); esperar | La reproducción continúa; la lista no cambia si no hay versión nueva | Corte, reinicio de vídeo, cambio de URL activa: guardar consola y estado | NOT TESTED |

### Bloque B — Navegación y estado

| ID | Objetivo / pasos | Resultado esperado | Fallo / información | Estado |
|---|---|---|---|---|
| B-01 | Panel: Left/Right entre Playlist/Favoritos/Fuentes | Pestañas cambian sin perder foco de forma errática | Foco atrapado, pestaña incorrecta: secuencia | NOT TESTED |
| B-02 | Playlist: FF, buscar texto, aceptar; borrar filtro | Lista filtrada y restaurada | Filtro no aplica o pierde foco: texto usado | NOT TESTED |
| B-03 | Recorrer lista de 500/2000 (fuente de spike) | Scroll fluido, sin solapamiento ni cierres | Lag, crash, logos superpuestos: modelo, cantidad, memoria | NOT TESTED |
| B-04 | Abrir/cerrar panel y volver a abrir | Foco regresa a un canal válido | Foco en 0 o pérdida total: estado previo | NOT TESTED |
| B-05 | Play sobre un canal; comprobar favorito; Play de nuevo | Favorito se agrega/quita; estado visual correcto | Favorito duplicado o no persiste: canal y secuencia | NOT TESTED |
| B-06 | Con favoritos, cerrar app y reabrir | Favoritos y última fuente se conservan | Pérdida/cambio de favoritos: captura antes/después | NOT TESTED |
| B-07 | Con fuente de laboratorio, agregar/eliminar/reordenar y actualizar mientras panel abierto; seleccionar inmediatamente | Foco seguro y canal seleccionado pertenece a la versión nueva | Reproduce URL eliminada/vieja o salta de ítem: anotar R-03/R-07 | NOT TESTED |

### Bloque C — Logos

| ID | Objetivo / pasos | Resultado esperado | Fallo / información | Estado |
|---|---|---|---|---|
| C-01 | Recorrer canales variados | Caja 58×36, contain, centrado, sin solape | Cualquier desborde/solape: foto, canal, hora | NOT TESTED |
| C-02 | Enfocar/deseleccionar filas | Misma geometría; solo cambia resaltado/foco | Logo cambia tamaño al enfocar: foto | NOT TESTED |
| C-03 | Abrir canal sin logo | Placeholder uniforme en caja | Hueco, logo enorme o texto desplazado | NOT TESTED |
| C-04 | Fuente de laboratorio con logo 404 | Placeholder; no bloquea lista | Crash, hueco o reintentos excesivos | NOT TESTED |
| C-05 | Lista de 2000 (spike) | Sin solapamiento; memoria estable | Cierre/lag: modelo y memoria | NOT TESTED |
| C-06 | Logos cuadrados, anchos, verticales, pequeños, grandes y PNG transparente | Todos contenidos/centrados, sin deformar | Deformación/recorte: archivo y proporción | NOT TESTED |

### Bloque D — Actualización M3U

Usar una fuente de laboratorio local; no modificar las fuentes reales del usuario.

| ID | Objetivo / pasos | Resultado esperado | Fallo / información | Estado |
|---|---|---|---|---|
| D-01 | Fuente sin cambios; pulsar Replay | “Lista al día”; sin parpadeo ni reinicio | Reconstrucción visible o recarga completa: captura | NOT TESTED |
| D-02 | Añadir un canal en la M3U local; Replay | Canal aparece tras validación; foco conservado | No aparece o pierde foco: antes/después | NOT TESTED |
| D-03 | Eliminar un canal; Replay | Desaparece de lista; si estaba reproduciendo, el vídeo continúa | Corte de reproducción o favorito borrado | NOT TESTED |
| D-04 | Cambiar URL de un canal; Replay | Lista usa nueva URL; sesión activa conserva URL anterior | Cambio de URL en vivo o reproducción incorrecta | NOT TESTED |
| D-05 | Detener servidor; Replay | Error controlado; se conserva última lista válida | Lista vacía, crash o bucle de reintentos | NOT TESTED |
| D-06 | Reproducir; modificar fuente; Replay | Vídeo, `m.playingUrl` y `m.current` intactos | Corte/reinicio/cambio de URL activa: R-01 | NOT TESTED |
| D-07 | Navegar mientras se actualiza (panel abierto) | Foco/pestaña/filtro/orden estable; sin parpadeo | Salto de foco o elemento viejo: R-03 | NOT TESTED |
| D-08 | Reiniciar app tras actualización; comprobar copia A/B | Última versión válida disponible; sin archivo parcial | Lista vacía/corrupta: consola y estado | NOT TESTED |

### Bloque E — Caché

| ID | Objetivo / pasos | Resultado esperado | Fallo / información | Estado |
|---|---|---|---|---|
| E-01 | Primera carga de una fuente nueva | Descarga y lista; luego caché disponible | Error inicial o lista vacía: servidor y consola | NOT TESTED |
| E-02 | Reabrir/Replay sin cambios | No se reescribe/renderiza; estado “al día” | Reconstrucción innecesaria o descarga completa | NOT TESTED |
| E-03 | Servir con `Last-Modified`; repetir con If-Modified-Since/curl y Replay | 304/no cambio; sin alterar lista | 200 repetido/recarga: logs del servidor | NOT TESTED |
| E-04 | Error de red y recuperación posterior | Conserva última versión; vuelve a actualizar al restaurar red | Pérdida de lista o bloqueo permanente | NOT TESTED |
| E-05 | Caché corrupta o pérdida total (`cachefs`) | Reparación o degradación controlada; sin crash | Crash o lista inválida: no corromper el dispositivo sin autorización | NOT TESTED/BLOCKED |

### Bloque F — EPG y metadatos

Requiere una fuente con base de metadatos local (`Fuentes > FF`) o el fixture.

| ID | Objetivo / pasos | Resultado esperado | Fallo / información | Estado |
|---|---|---|---|---|
| F-01 | Configurar base local; abrir app; comprobar manifiesto | `latest.json` cargado; sin error de UI | Metadata no aparece: URL, servidor, consola | NOT TESTED |
| F-02 | Comprobar catálogo/logos de catálogo | Catálogo aplicado sin bloquear lista | Logo no actualiza o lista parpadea | NOT TESTED |
| F-03 | Enfocar canal con EPG | Tarjeta muestra ahora/siguiente, horas y descripción | Tarjeta vacía o texto desbordado: canal | NOT TESTED |
| F-04 | Avanzar foco entre canales | Tarjeta cambia al canal correcto; sin lag | Datos de otro canal o foco perdido | NOT TESTED |
| F-05 | Esperar 30–60 s | Barra de progreso avanza; no hay red por foco | Progreso congelado/incorrecto | NOT TESTED |
| F-06 | Canal con programa sin `stop` (fixture Gamma) | “Duración desconocida”; sin barra; no inventa fin | Progreso/fin inventado | NOT TESTED |
| F-07 | Cambiar zona horaria del dispositivo | Horas locales coherentes; no se inventa duración | Hora incorrecta: zona y hora del dispositivo | NOT TESTED |
| F-08 | Canal sin correspondencia EPG (Delta) | “Sin información de programación”; no bloquea | Crash o tarjeta con datos ajenos | NOT TESTED |
| F-09 | Fuente sin base de metadatos | Sin tarjeta EPG; lista y reproducción normales | Errores de red/UI | NOT TESTED |
| F-10 | Configurar shards superando el umbral | Carga y fusión de shards sin duplicados | Falta programación o error: manifest/servidor | NOT TESTED |

## 6. Secuencia de ejecución

Ejecutar **un bloque cada vez** y esperar resultados antes de continuar:

1. **P0** (P0-01 a P0-03): arranque, diagnóstico y geometría base.
2. **A** (A-01 a A-06): reproducción y actualización en segundo plano.
3. **B** (B-01 a B-07): navegación, foco y favoritos.
4. **C** (C-01 a C-06): logos con proporciones y fallos.
5. **D** (D-01 a D-08): actualización M3U controlada.
6. **E** (E-01 a E-05): caché y recuperación.
7. **F** (F-01 a F-10): EPG y metadatos.

Para cada ejecución registrar: ID, fecha/hora, modelo/OS, fuente, canal, pasos,
resultado observado, PASS/FAIL/BLOCKED, captura o foto y líneas de consola.

## 7. Diagnóstico por tipo de fallo

- **Crash/SceneGraph:** consola 8085; `bt`, `last`, `var`, `threads`; anotar
  línea y último estado.
- **Reproducción:** `query/media-player`, estado del `Video`, URL/canal; no
  cambiar `content.url` ni `m.current` durante la prueba.
- **Descarga M3U/EPG:** logs del servidor local, `curl` del manifiesto/artefacto,
  estado visible; la app no imprime el motivo HTTP.
- **Caché:** no borrar archivos manualmente sin autorización; usar reinicio y
  servidor compartido para forzar fallos controlados.
- **Memoria:** Roku Resource Monitor si está disponible; anotar modelo y OS.
- **Foco/navegación:** foto antes/después y secuencia exacta de teclas.

## 8. Pruebas que requieren hardware

Todas las de la matriz (P0, A–F) requieren Roku físico. Las suites Python/BRS
solo prueban lógica pura/estática. No se declara ninguna PASS física.

## 9. Defectos potenciales prioritarios

1. R-03: selección con `m.view` obsoleto tras reordenamiento.
2. R-01/R-02: carreras de flags entre tareas al cambiar de fuente.
3. R-04: ausencia de logs de diagnóstico de HTTP/caché.
4. R-05: descarga de metadata sin timeout explícito.
5. R-06: coste de hash/validación M3U en hardware de baja gama.
6. R-09/R-10: legibilidad EPG y expectativa de zona horaria.

## 10. Primera prueba recomendada

**P0-01 — Arranque y lista base.**

Pasos: abrir la app desde Home, esperar la lista, abrir el panel con Back y
comprobar que el foco está en un canal. Resultado esperado: lista visible, sin
crash ni excepción en `telnet IP 8085`. Si falla, guardar consola, modelo/OS,
captura y estado de la fuente activa.

No ejecutar A–F hasta recibir el resultado de P0.


## 12. Ampliación: EPG automática y grilla completa

Estado inicial: **NOT TESTED**. El servidor se instaló en Debian (`roku-epg.service`,
puerto 8001) y la app genera la URL de metadatos automáticamente. No declarar PASS
hasta ejecutar en el Roku físico.

| ID | Objetivo / pasos | Resultado esperado | Fallo / información | Estado |
|---|---|---|---|---|
| SRV-01 | `systemctl --user status roku-epg.service` y `pipeline/server/healthcheck.sh` | Servicio enabled/active; health OK | Servicio caído o health FAIL: logs/journal | NOT TESTED |
| SRV-02 | Abrir `/real/latest.json`, `/catalog.json`, `/epg.json`, `/coverage.json` desde el host | 200, `application/json`, JSON válido | 404, HTML o JSON inválido | NOT TESTED |
| SRV-03 | Comprobar `http://192.168.1.7:8000/` | El servidor de películas sigue funcionando | Puerto 8000 alterado: detener prueba | NOT TESTED |
| CFG-01 | Instalar el paquete final y abrir app; no tocar Fuentes | Metadatos cargan automáticamente; no hay que escribir URL | Estado sin EPG: revisar `sources` y logs | NOT TESTED |
| CFG-02 | Inspeccionar `sources`; comprobar que la URL M3U original no cambió | Misma URL M3U; solo aparece `meta` para robinpalat/streams | URL M3U alterada o fuente eliminada | NOT TESTED |
| GRID-01 | Playlist: enfocar `Guía EPG` y pulsar OK | Se abre la grilla a pantalla completa | No abre o crash | NOT TESTED |
| GRID-02 | En grilla, Up/Down | Cambia de canal; foco y detalle se actualizan | Salto incorrecto o crash | NOT TESTED |
| GRID-03 | En grilla, Left/Right | Cambia de programa/ventana temporal con bloques proporcionales y selección clara | Ventana bloqueada o desbordes | NOT TESTED |
| GRID-04 | Seleccionar programa y OK | Se muestra título, horas y descripción | Detalle vacío o incorrecto | NOT TESTED |
| GRID-05 | Canal sin EPG (p. ej. CinePride) | Bloque “Sin programación”; no bloquea navegación | Crash o datos ajenos | NOT TESTED |
| GRID-06 | Comparar línea “Ahora” con reloj | Línea en la posición temporal correcta | Línea ausente/incorrecta | NOT TESTED |
| GRID-07 | Back desde grilla | Vuelve al panel; foco válido; no reinicia app | Atrapado en grilla o reinicio | NOT TESTED |
| GRID-08 | Reproducir canal, abrir grilla y volver | Vídeo, URL activa y audio continúan | Corte o cambio de URL | NOT TESTED |
| GRID-09 | Reiniciar app y abrir grilla | EPG se recupera desde caché/servidor; sin crash | Grilla vacía permanente | NOT TESTED |
| GRID-10 | Recorrer canales/ventanas durante 2–3 min en Roku Express | Navegación fluida; sin cierre por memoria | Lag/crash: anotar modelo y nodos | NOT TESTED |

La corrección funcional mínima se considera lista para prueba física cuando SRV-01
y SRV-02 estén en PASS **en el host**, y CFG-01/GRID-01..09 se ejecuten en el Roku.
