# Diagnóstico EPG en Roku: programación ausente

Proyecto: `streams-roku`  
Roku: `Roku Express` (`model-number 3960RW`), IP `192.168.1.9`, Roku OS `15.3.4`  
Host de artefactos: `192.168.1.7`  
Fecha: 2026-11-21  
Alcance: diagnóstico. **No se modificó código ni se implementó la grilla.**

## 1. Resumen ejecutivo

La causa principal está demostrada: **Roku no tiene configurada ninguna URL base de
metadatos**. El registro de la app contiene las tres fuentes por defecto sin campo
`meta`; las claves `meta_base` y `meta_d` están vacías. Por tanto
`StartMetadata()` no inicia `MetadataTask`, `m.catalog`/`m.epg` permanecen
inválidos y `UpdateEpgCard()` muestra “Sin información de programación” para todos
los canales. Los logos sí aparecen porque provienen de `tvg-logo` de la M3U, no del
catálogo/EPG.

Además, el puerto 8000 del host no sirve `pipeline/out/`; actualmente sirve otro
directorio (`/media/Files/Downloads/Peliculas`). Aunque se configurara una URL
`http://192.168.1.7:8000/real/`, esa ruta devuelve 404. El servidor local del
pipeline sí funciona en un puerto alternativo (probado en 18084).

La grilla EPG completa **no existe en esta versión**: el único componente actual es
la tarjeta de ahora/siguiente dentro del panel. Por tanto, la ausencia de grilla es
esperada; el fallo es la ausencia de datos en esa tarjeta.

## 2. Recorrido real de los datos

```text
XMLTV reales (pipeline/real/guide-*.xml)
  -> pipeline.build
  -> pipeline/out/real/{latest,catalog,epg,coverage}.json   [VÁLIDOS]
  -> host HTTP :8000  -> sirve /media/Files/Downloads/Peliculas [RUTA INCORRECTA]
     /real/latest.json -> 404
  -> Roku:
       sources registry: sin campo meta
       meta_base = "" / meta_d = ""
       MetaBase() = "" -> StartMetadata() retorna
       MetadataTask no se inicia
       m.catalog = invalid, m.epg = invalid
       UpdateEpgCard() -> "Sin información de programación"
```

La ruta de datos se interrumpe antes de la descarga Roku, no en la asociación ni en
la tarjeta.

## 3. URL configurada y URL efectiva

### Hechos

- `query/device-info` confirmó IP `192.168.1.9`, modelo `3960RW`, OS `15.3.4`.
- La consola BrightScript 8085 permitió leer el registro:
  - `sources` contiene las tres fuentes por defecto con `id/name/url`, **sin `meta`**.
  - `meta_base` devolvió cadena vacía.
  - `meta_d` devolvió cadena vacía.
- La app se encontraba reproduciendo `Cine Sony (720p)` con la lista cacheada
  (51 canales).
- `query/sgnodes/all` mostró:
  - `epgCard` visible al abrir el panel.
  - `epgName = "Cine Sony (720p)"`.
  - `epgNowTitle`, `epgNowTime`, `epgDesc`, `epgNextTitle` vacíos.
  - `epgStatus = "Sin información de programación"`.

### Conclusión

La **URL efectiva de metadatos en Roku es ninguna**. No hay una URL configurada
que apunte a `/real/`, `/fixture/` u otra ruta.

Un intento de URL probable (`http://192.168.1.7:8000/real/`) tampoco funcionaría
porque el puerto 8000 no sirve ese directorio.

## 4. Resultado de solicitudes HTTP

### Servidor actual en puerto 8000

El proceso es `servir_carpeta.py` con cwd `/home/robin` y sirve
`/media/Files/Downloads/Peliculas`.

| Solicitud | Resultado |
|---|---|
| `http://192.168.1.7:8000/` | 200; listado del directorio de Películas |
| `http://192.168.1.7:8000/real/latest.json` | **404**, HTML de error |
| `http://192.168.1.7:8000/fixture/latest.json` | **404**, HTML de error |

### Servidor local del pipeline en puerto alternativo

Se inició temporalmente `python3 -m pipeline.serve --dir pipeline/out --port 18084`
sin modificar la app. Resultados:

| Ruta | HTTP | Content-Type | Bytes | JSON |
|---|---:|---|---:|---|
| `/real/latest.json` | 200 | `application/json` | 560 | válido |
| `/real/catalog.json` | 200 | `application/json` | 17.875 | válido |
| `/real/epg.json` | 200 | `application/json` | 89.976 | válido |
| `/real/coverage.json` | 200 | `application/json` | 7.316 | válido |

El host es `192.168.1.7`; la ruta `/real/` existe en `pipeline/out/real/`. El
problema del puerto 8000 es la configuración del servidor, no los archivos.

## 5. Estado de manifiesto, catálogo y EPG

Los artefactos reales son consumibles y coherentes:

- `latest.json`: schema 1, referencias a `catalog.json` y `epg.json`, versiones y
  hashes. Generado el 2026-11-21 22:28:56 UTC.
- `catalog.json`: 40 canales con `tvg-id`, `epgId`, logo y metadatos.
- `epg.json`: 18 entradas de canal, 326 programas en la ventana 24 h + 6 h.
- `coverage.json`: 51 canales M3U, 40 mapeados, 17 con programas, 23 sin
  programas, 11 sin `tvg-id`; cobertura efectiva 33,3%.
- `pipeline.validate --out pipeline/out/real` devuelve OK.
- `CinePride.us@SD` tiene 0 programas; no se inventó programación.
- `distro.tv` falló por DNS (`getaddrinfo ENOTFOUND tv.jsrdn.com`); queda
  registrado en `sourceErrors`.

No se ha demostrado ningún error en el generador real.

## 6. Ejemplos de asociaciones

La asociación que usaría la app es por `tvg-id`; no por nombre.

| M3U (`tvg-id`) | Catálogo | EPG (`epg.json`) | Resultado esperado |
|---|---|---|---|
| `Mega.cl@SD` | clave `Mega.cl@SD` | 7 programas en la ventana | Debe mostrar ahora/siguiente |
| `13C.cl@SD` | clave `13C.cl@SD` | 16 programas | Debe mostrar ahora/siguiente |
| `24Horas.es@SD` | clave `24Horas.es@SD` | 32 programas | Debe mostrar ahora/siguiente |
| `Space.ar@Panregional` | clave `Space.ar@Panregional` | 6 programas | Debe mostrar ahora/siguiente |
| `DW.de@Espanol` | clave `DW.de@Espanol` | 51 programas | Debe mostrar ahora/siguiente |
| `CinePride.us@SD` | clave presente | 0 programas | “Sin información de programación” |
| `TVEInternacionalEurope.es@HD` | clave presente | sin entrada de feed HD | Sin programación; no se reutiliza SD |
| `LoveNature.ca@HD` | clave presente | sin entrada de feed HD | Sin programación; no se reutiliza SD |
| `m3u.cl` | sin `tvg-id` | no aplica | Sin asociación automática |

Las claves coinciden exactamente; no se observan diferencias de mayúsculas,
espacios o sufijos en los canales con programas.

**No se llegó a ejecutar esta asociación en Roku** porque `m.epg` permanece
inválido al no configurarse metadatos.

## 7. Causa raíz e hipótesis

### Causa raíz demostrada

1. `sources` en el registro no contiene `meta`.
2. `meta_base` y `meta_d` están vacíos.
3. `MetaBase()` (`MainScene.brs:737-743`) devuelve `""`.
4. `StartMetadata()` (`MainScene.brs:745-755`) retorna sin iniciar la tarea.
5. `m.catalog`/`m.epg` nunca se llenan; `UpdateEpgCard()` (`MainScene.brs:827`)
   muestra “Sin información” para todos los canales.
6. El servidor del puerto 8000 no sirve `/real/`; una URL hacia ese puerto
   devolvería 404.

### Hipótesis / aspectos a validar

- **H-01 (alta):** el usuario no encontró cómo configurar la URL de metadatos.
  La única vía es Fuentes -> FF; en una prueba por ECP, pulsar Fwd sobre una
  fuente no mostró el diálogo esperado y devolvió el foco al primer elemento.
  Puede deberse a que `MarkupList` consume FastForward o a que el diálogo no se
  reflejó en `/query/sgnodes`. Requiere reproducirlo con el mando físico.
- **H-02 (media):** si el usuario configuró `http://192.168.1.7:8000/real/`, el
  404 del servidor impide toda descarga. No hay evidencia en el registro de que
  esa URL se haya guardado.
- **H-03 (media):** el usuario esperaba una “grilla”; esa vista no existe en esta
  versión. Solo existe la tarjeta dentro del panel, visible al enfocar un canal.

## 8. Archivos y funciones implicados

- `source/util.brs`: `RegRead`, `RegWrite`, `NowSeconds`, `JoinUrl`.
- `components/MainScene.brs`:
  - `init()`: inicia `LoadPlaylist` y `StartMetadata` (`:56-75`).
  - `MetaBase()`/`GetSourceMeta()`: resuelven `src.meta`, `meta_<id>` o `meta_base` (`:731-743`).
  - `StartMetadata()`: retorna si no hay base (`:745-755`).
  - `onMetadata()`: actualiza catálogo/EPG (`:757-776`).
  - `onListFocused()`/`UpdateEpgCard()`: presentación ahora/siguiente (`:785-854`).
  - `onKeyEvent()`: FF para metadatos en Fuentes (`:952-965`).
- `components/MetadataTask.brs`: descarga manifiesto/catálogo/EPG versionados
  (`:8-145`).
- `source/epg.brs`: `EpgSelectNowNext`, `EpgTimeRange`.
- `source/catalog.brs`: `CatalogEpgIdForItem`.
- `components/MainScene.xml`: `epgCard`, `epgNowTitle`, `epgStatus` (`:19-34`).
- `pipeline/out/real/`: artefactos válidos.
- `pipeline/serve.py`: servidor local probado en 18084.
- Servidor actual del puerto 8000: `/home/robin/.local/bin/servir_carpeta.py`,
  cwd `/home/robin`, sirviendo `/media/Files/Downloads/Peliculas`.

Además, la consola mostró advertencias de SceneGraph:

```text
Warnings occurred while creating XML component MainScene
-- Tried to set nonexistent field "width" of a "RenderableNode" node
-- Tried to set nonexistent field "height" of a "RenderableNode" node
```

No son la causa de la EPG ausente, pero indican atributos `width`/`height` en un
`Group` que no los admite. Se dejan como hallazgo separado.

## 9. Corrección mínima recomendada

No implementada todavía:

1. Servir `pipeline/out` en un puerto libre (por ejemplo 8001 o 18084), porque
   8000 ya está ocupado por otro servidor:
   `python3 -m pipeline.serve --dir pipeline/out --port 8001`.
2. En Roku, abrir **Fuentes**, enfocar la fuente activa y pulsar **FF**; introducir
   `http://192.168.1.7:8001/real/` (no `localhost`, no `127.0.0.1`).
3. Confirmar que la ruta sea accesible desde Roku; el host es `192.168.1.7` y el
   Roku `192.168.1.9` están en la misma LAN.
4. Verificar en la tarjeta de un canal con EPG (`Mega.cl@SD`, `13C.cl@SD`,
   `24Horas.es@SD`, `DW.de@Espanol`) que aparecen ahora/siguiente.
5. Si FF no abre el diálogo de metadatos con el mando físico, corregir localmente
   la accesibilidad de esa acción (posible conflicto con `MarkupList`); no es una
   corrección de datos.
6. No se requiere una grilla para esta validación: la vista actual es la tarjeta
   de ahora/siguiente.

## 10. Pruebas para verificar la corrección

| ID | Acción | Resultado esperado |
|---|---|---|
| D-EPG-01 | Servir `pipeline/out` en 8001 y comprobar `/real/latest.json` desde el host | 200, JSON, 560 B |
| D-EPG-02 | Configurar `http://192.168.1.7:8001/real/` en Fuentes > FF | Diálogo acepta y guarda la URL |
| D-EPG-03 | Reabrir la app y abrir panel en `Mega.cl@SD` | Tarjeta con programa actual y siguiente |
| D-EPG-04 | Enfocar `13C.cl@SD`/`24Horas.es@SD` | Tarjeta cambia al canal correcto |
| D-EPG-05 | Enfocar `CinePride.us@SD` | “Sin información de programación” |
| D-EPG-06 | Esperar 30–60 s | Progreso avanza sin red por foco |
| D-EPG-07 | Reproducir un canal mientras se actualiza metadata | Vídeo/URL actuales intactos |
| D-EPG-08 | Reiniciar app | Manifiesto/caché recuperados; tarjeta sigue funcionando |
| D-EPG-09 | Inspeccionar `telnet 192.168.1.9 8085` | Sin errores de descarga/JSON; sin warnings nuevos |

Separar siempre: las pruebas de generación/HTTP son locales; D-EPG-02..08 son
físicas en Roku.

## 11. Limitaciones y notas

- No se implementó ninguna corrección ni grilla.
- No se modificó la app; la intervención de consola incluyó una pausa y salida de
  la app para leer el registro. El dispositivo quedó en Home; volver a abrir la
  app desde el instalador/desarrollador cuando corresponda.
- La lectura del registro se hizo mediante la consola BrightScript; no se pudo
  usar `query/registry` por la respuesta “Device not keyed”.
- La EPG real tiene 33,3% de cobertura efectiva; los canales sin datos deben
  mostrar el estado vacío, no inventar programación.
- La grilla completa queda fuera de alcance.
