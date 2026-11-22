# Informe de implementación — Logos, EPG y actualización dinámica M3U

Proyecto: `/home/robin/1Devin/Projects/streams-roku`
Fecha: 2026-11-21
Especificación: `PLAN_INTEGRACION_LOGOS_EPG(3)(1).md`

## 1. Resumen

Se implementó una integración local y aditiva para:

- captura de `tvg-id`, `tvg-name` y `tvg-logo`;
- actualización cache-first de M3U con validación, hash, slots A/B, sidecars,
  anomalías, cuarentena y reconciliación;
- logos en `MarkupList` con componente `ChannelItem`, caja fija 58×36, contain y centrado;
- pipeline local de catálogo, EPG de 24 h + 6 h, cobertura, manifiesto y shards;
- `MetadataTask` para catálogo/EPG versionados;
- tarjeta de ahora/siguiente con descripción y progreso;
- refresco periódico de M3U y metadatos.

No se modificó el contrato de reproducción, zapping, subtítulos, favoritos
existentes ni navegación. No se creó infraestructura externa ni se publicó nada.

## 2. Fases

| Fase | Estado | Limitación |
|---|---|---|
| 0. Línea base y tests | Completada documental y localmente | Sin dispositivo Roku |
| 1. Modelo, parser y generador local | Completada | Datos de API son fixtures locales |
| 1B. Actualización dinámica M3U | Implementada y validada en lógica pura/compilación | HTTP, slots y cachefs reales pendientes de hardware |
| 2. Logos y geometría | Implementados con `MarkupList` + `ChannelItem` | Spike y memoria real pendientes de hardware |
| 3. EPG 24 h + 6 h | Pipeline y tarjeta implementados | EPG real integrada: 17/51 (33,3%); ver `docs/EPG_REAL_INFORME.md` |
| 4. Caché/manifiesto | Implementado | Descarga real y `cachefs` pendientes de hardware |
| 4B. Refresco/reconciliación | Implementado | Comportamiento de foco/UI pendiente de hardware |
| 5. Rejilla EPG | Excluida | No implementada |

## 3. Arquitectura final

```text
M3U remota/local
  -> PlaylistTask (Task)
       -> cache-first desde slots A/B + sidecars
       -> GET condicional (ETag/If-None-Match, Last-Modified/If-Modified-Since)
       -> hash normalizado si no hay validadores
       -> validación + diff + anomalías + cuarentena
       -> commit al slot inactivo + índice central
  -> MainScene
       -> canales y reconciliación de foco/orden
       -> MarkupList + ChannelItem (caja fija, contain, centrado)
       -> tarjeta EPG ahora/siguiente
  -> MetadataTask (Task)
       -> latest.json
       -> catalog.json solo si cambia/missing/corrupto
       -> epg.json o shards solo si cambia/missing/corrupto
  -> cachefs versionado; registro solo para ajustes pequeños
```

Pipeline local:

```text
pipeline/config/sources.json
  -> M3U + XMLTV + snapshots API locales
  -> catalog.json
  -> epg.json (24 h + 6 h; sin stop = duración desconocida)
  -> coverage.json (efectiva, no potencial)
  -> latest.json (+ shards epg_<grupo>.json si hace falta)
```

## 4. Archivos

### Creados

- `source/m3u_parser.brs`
- `source/m3u_update.brs`
- `source/catalog.brs`
- `source/epg.brs`
- `components/MetadataTask.xml`
- `components/MetadataTask.brs`
- `components/ChannelItem.xml`
- `components/ChannelItem.brs`
- `source/logo_geometry.brs`
- `images/logo_placeholder.png`
- `pipeline/__init__.py`
- `pipeline/build.py`
- `pipeline/catalog.py`
- `pipeline/coverage.py`
- `pipeline/grab_epg.py`
- `pipeline/m3u.py`
- `pipeline/serve.py`
- `pipeline/spike_m3u.py`
- `pipeline/validate.py`
- `pipeline/xmltv.py`
- `pipeline/config/sources.json`
- `pipeline/fixtures/streams.m3u`
- `pipeline/fixtures/guide.xml`
- `pipeline/fixtures/aliases.json`
- `pipeline/fixtures/api/channels.json`
- `pipeline/fixtures/api/feeds.json`
- `pipeline/fixtures/api/logos.json`
- `pipeline/tests/test_build.py`
- `pipeline/tests/test_epg.py`
- `pipeline/tests/test_m3u.py`
- `pipeline/tests/test_ui_geometry.py`
- `pipeline/tests/test_real_epg.py`
- `pipeline/README.md`
- `tests/brs/m3u_update_test.brs`
- `tests/brs/package.json`
- `tests/run_brs_tests.sh`
- `docs/BASELINE.md`
- `docs/SPIKE_LABELLIST.md`
- `docs/IMPLEMENTACION_INFORME.md`
- `docs/EPG_REAL_INFORME.md`

### Modificados

- `manifest` (`build_version=18`)
- `source/util.brs` (helpers de tiempo, claves y URL)
- `components/PlaylistTask.xml` (campos/modo/scripts)
- `components/PlaylistTask.brs` (reescrito para cache-first, validación, slots y HTTP condicional)
- `components/MainScene.xml` (tarjeta EPG, `MetadataTask`, timers, scripts)
- `components/MainScene.brs` (orquestación, iconos, EPG, reconciliación, meta de fuente)

### Eliminados

- Ninguno. Las funciones de parseo se movieron de `PlaylistTask.brs` a
  `source/m3u_parser.brs` conservando su comportamiento.

## 5. Pipeline local

- No usa GitHub Actions, Pages, APIs, bases de datos ni hosting.
- `pipeline/config/sources.json` apunta a fixtures locales por defecto.
- `pipeline/grab_epg.py` es un envoltorio opcional para ejecutar un checkout local
  de `iptv-org/epg`; no está programado ni publica.
- `pipeline/out/fixture` contiene artefactos de ejemplo generados.
- `pipeline/out/spike/logo.png` y `pipeline/spike_m3u.py` preparan el spike de listas/logos.

## 6. Comandos

```bash
# Pruebas del pipeline
python3 -m unittest discover -s pipeline/tests -v

# Pruebas BrightScript puras (requiere brs, solo desarrollo)
npm install --prefix tests/brs
BRS=tests/brs/node_modules/.bin/brs tests/run_brs_tests.sh

# Validación estática/paquete Roku
bsc --create-package false --diagnostic-level error
bsc --create-package true --diagnostic-level error

# Generar artefactos con ventana fija reproducible
python3 -m pipeline.build \
  --config pipeline/config/sources.json \
  --out pipeline/out \
  --now 2026-11-21T06:00:00Z

# Validar artefactos
python3 -m pipeline.validate --out pipeline/out/fixture

# Servir en local para el Roku
python3 -m pipeline.serve --dir pipeline/out --port 8000

# Grabador EPG opcional, si hay checkout local de iptv-org/epg
python3 -m pipeline.grab_epg \
  --epg-repo /ruta/a/epg \
  --sites mi.tv,gatotv.com \
  --out pipeline/fixtures/generated/guide.xml \
  --days 2
```

En la app: **Fuentes** -> enfocar fuente -> **FF** -> URL base de metadatos
(`http://IP:8000/fixture/`).

## 7. Resultados reales de pruebas

| Suite | Resultado |
|---|---|
| `pipeline/tests` | 64 aprobadas, 0 fallidas |
| `tests/brs` | 62 aprobadas, 0 fallidas, 6 pendientes de hardware/simulación |
| BrighterScript compile | 0 errores |
| Paquete BrighterScript | 29 archivos, ~2,0 MB |
| Pipeline build + validate | OK |
| Servidor local HTTP | `latest.json` 200/557 B; `epg.json` 200/1378 B |
| Fuente real `robinpalat/streams` | 51 canales, 40 `tvg-id`, 40 `tvg-logo` |
| Fuente real `m3u.cl` | 19 canales, 0 `tvg-id`, 19 `tvg-logo` |

No se han ejecutado pruebas de reproducción, foco, `MarkupList`/`ChannelItem`, `cachefs` ni
`roUrlTransfer` en un Roku real.

## 8. Matriz M3U de 32 escenarios

A = automatizado; P = parcial (lógica pura o pipeline; I/O real pendiente);
H = pendiente de hardware/red.

| # | Escenario | Estado |
|---:|---|---|
| 1 | Fuente sin cambios | P (hash/diff; 304 real pendiente) |
| 2 | Canal nuevo | A |
| 3 | Canal eliminado | A |
| 4 | Cambio de URL | A |
| 5 | Cambio de nombre/grupo | A |
| 6 | Cambios masivos legítimos | P (cuarentena/confirmación pura; slots pendientes) |
| 7 | HTML | A |
| 8 | Truncada | A |
| 9 | Vacía | A |
| 10 | HTTP 500 | H |
| 11 | Timeout | H |
| 12 | DNS fallido | H |
| 13 | Desconexión durante descarga | H |
| 14 | Reinicio durante actualización | H |
| 15 | Caché ausente/evictada | H |
| 16 | Reproduciendo mientras cambia | H |
| 17 | Navegando mientras cambia | H |
| 18 | Favorito de canal eliminado | P (código preserva; UI sin hardware) |
| 19 | Mismo `tvg-id`, URLs distintas | A |
| 20 | Cambios frecuentes con igual cantidad | P (hash/diff; scheduler real pendiente) |
| 21 | 100 canales, 80 URLs sustituidas | A |
| 22 | Cambio masivo de `tvg-id` | A |
| 23 | Cambio masivo de grupos | A |
| 24 | Duplicación masiva de URLs | A |
| 25 | Metadatos centrales corruptos, dos slots | P (selección pura; archivos reales pendientes) |
| 26 | Metadatos corruptos, generaciones distintas | P (selección pura; archivos reales pendientes) |
| 27 | Pérdida total de `cachefs` | H |
| 28 | Reinicio con caché conservada | H |
| 29 | Protocolo admitido distinto de HTTP/HTTPS | A (`rtsp` en parser; reproducción real pendiente) |
| 30 | XMLTV con `start` y sin `stop` | A |
| 31 | Manifiesto sin cambios y `refreshAfter` vencido | P (versionado/determinismo; descarga real pendiente) |
| 32 | Caché de artefacto corrupta con versión igual | H |

Resumen: 14 automatizadas, 7 parciales, 11 pendientes de hardware/red. No se
declaran aprobadas las pendientes.

## 9. Regresión

Verificación estática contra la copia de línea base:

- `StartPlayback`, `Zap`, `ZapList`, `CycleSubtitles`, `ScheduleRetry` y
  `onVideoState`: sin cambios de cuerpo.
- `PlayChannel`: solo añade campos opcionales al objeto temporal; no cambia
  `m.current`, `m.playingUrl`, `content.url`, `streamFormat` ni el flujo.
- Navegación, pestañas, filtros y favoritos existentes: conservados.
- Replay en panel ahora lanza un chequeo condicional en lugar de recargar la
  lista completa; la reproducción no se toca.

Pendiente de hardware: demostrar reproducción, zapping, subtítulos, foco,
favoritos y ausencia de interrupciones en un dispositivo real.

## 10. Métricas disponibles

Artefactos del fixture:

| Archivo | Bytes |
|---|---:|
| `latest.json` | 557 |
| `catalog.json` | 1736 |
| `epg.json` | 1378 |
| `coverage.json` | 992 |

- Paquete Roku compilado: ~2,0 MB, 29 archivos.
- No hay mediciones de memoria, p95 ni peticiones de imagen en hardware.
- La ventana de iconos es ±8 elementos; evita asignar iconos a 2000 filas de golpe.

## 11. Cobertura efectiva EPG

Fixture local (7 canales M3U):

- mapeados: 5/7 (71,4% potencial);
- con programas: 4/7 (57,1% efectiva);
- sin programas: 1 (Beta);
- sin `tvg-id`/no mapeado: 1 (Delta);
- duración desconocida: 1 (Gamma, sin `stop`);
- cobertura parcial: 3 (A, C, E/F según `endKnown`);
- fallidos: 0.

Se ejecutaron grabadores reales de `iptv-org/epg` para la fuente
`robinpalat/streams`; la cobertura efectiva medida es 17/51 (33,3%). El detalle
de fuentes, correspondencias, XMLTV y limitaciones está en
`docs/EPG_REAL_INFORME.md`. No se publicaron datos ni se declaró cobertura total.

## 12. Licencias

- No se descargaron ni redistribuyeron logos de tv-logos.
- `tvg-logo` y `logos.json` se usan como referencias; la licencia de cada imagen
  debe revisarse antes de distribuirla.
- La EPG de cada sitio requiere revisar sus términos. No se publicó nada.

## 13. Validación pendiente en hardware Roku

- Spike de `MarkupList`/`ChannelItem` con 50/500/2000 canales y memoria/texturas.
- Carga de iconos, recorte/centrado y geometría real de la caja 58×36.
- `AsyncGetToString`, cabeceras ETag/Last-Modified, 304, timeout y gzip.
- `roFileSystem`/`cachefs` en slots A/B, sidecars y pérdida total.
- Reproducción, zapping, subtítulos, foco, favoritos y actualización en segundo plano.
- `MetadataTask` con HTTP real, manifiesto, shards y reparación de caché.
- Tarjeta EPG con `roDateTime`, zonas horarias y programas sin `stop`.

## 14. Riesgos residuales

- La geometría se validó matemáticamente y por XML, pero no en pantalla Roku.
- `cachefs` puede expulsar todo; A/B solo protege si quedan archivos.
- Los validadores HTTP pueden no ser respetados por todas las fuentes.
- El hash/parseo de M3U grandes debe medirse en hardware.
- Las licencias de EPG siguen requiriendo revisión; la cobertura real medida es 17/51.
- La UI de tarjeta EPG ocupa 390 px; títulos largos pueden recortarse.
- El pipeline usa fixtures locales; la API/fuentes reales requieren snapshots o red.
- No hay tests automáticos de SceneGraph/Task en hardware.

## 15. Instrucciones exactas

1. Generar artefactos:

```bash
cd /home/robin/1Devin/Projects/streams-roku
python3 -m pipeline.build --config pipeline/config/sources.json --out pipeline/out
```

2. Validar:

```bash
python3 -m pipeline.validate --out pipeline/out/fixture
```

3. Servir en la red local:

```bash
python3 -m pipeline.serve --dir pipeline/out --port 8000
```

4. En la app Roku: **Fuentes** -> fuente -> **FF** -> `http://IP-DEL-PC:8000/fixture/`.

5. Para EPG real, generar XMLTV con `pipeline.grab_epg` o con `iptv-org/epg`,
   añadirlo a `epg` en `sources.json` y regenerar.

6. Pruebas:

```bash
python3 -m unittest discover -s pipeline/tests -v
npm install --prefix tests/brs
BRS=tests/brs/node_modules/.bin/brs tests/run_brs_tests.sh
bsc --create-package false --diagnostic-level error
```

No se ha publicado ni desplegado nada. La autorización de Fase 5 sigue excluida.

## 16. Corrección de geometría de logos (2026-11-21)

### Causa raíz

`LabelList` expone `HDListItemIconURL`/`HDListItemIconSelectedURL`, pero **no
ofrece ninguna propiedad documentada para fijar el ancho, alto, modo de escalado
o caja del icono**. Los iconos se entregaban como URLs con dimensiones originales
muy dispares y se dibujaban sin un contenedor de geometría fija, lo que produjo
logos de tamaños distintos y superposición entre filas. No era un problema de
los archivos de imagen ni del parser.

### Solución

Se reemplazó únicamente el nodo de presentación:

- `LabelList` -> `MarkupList` vertical con `itemComponentName="ChannelItem"`.
- `ChannelItem` extiende `Group` y crea una caja fija:
  - fila de 44 px, `itemSpacing [0,4]`;
  - `Poster` de 58×36 en `[8,4]`, `loadDisplayMode="limitSize"`;
  - `FitLogoInBox()` calcula escala `contain` y centra el bitmap dentro de 58×36;
  - el fondo de la fila ocupa 790×44 y el texto empieza en x=76;
  - placeholder local para logo ausente o fallido.
- Se eliminaron las asignaciones `HDListItemIconURL` y la ventana de iconos
  anterior. `MarkupList` crea componentes solo para elementos visibles.

### Alternativas

`RowList` también permite componentes personalizados, pero para una lista
vertical obliga a usar una fila por canal o cambia la semántica de navegación
horizontal. `MarkupList` conserva `itemFocused`, `itemSelected` y `jumpToItem`,
por lo que fue la opción más estable y con menor impacto en la app.

### Archivos de esta corrección

- Creados: `components/ChannelItem.xml`, `components/ChannelItem.brs`,
  `source/logo_geometry.brs`.
- Modificados: `components/MainScene.xml`, `components/MainScene.brs`.
- Tests nuevos: `pipeline/tests/test_ui_geometry.py` y casos de geometría en
  `tests/brs/m3u_update_test.brs`.

### Pruebas

- XML/estructura: caja 58×36, fila 44, separación 4, texto x=76, sin `LabelList`
  ni `HDListItemIcon*`.
- Matemática `FitLogoInBox`: cuadrado, horizontal ancho, vertical, pequeño e
  inválido; todos contenidos y centrados.
- Compilación BrighterScript: 0 errores.
- Suite local: 64 pruebas Python, 62 aserciones BrightScript, 0 fallos.

### Límite pendiente

No hay Roku físico en este entorno. **No se declara resuelto visualmente** hasta
probar en dispositivo con logos cuadrados, muy anchos, verticales, pequeños,
grandes, transparentes y URLs fallidas, en listas de 50/500/2000 canales, y
confirmar foco, selección y ausencia de solapamiento en pantalla real.
