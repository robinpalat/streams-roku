# EPG real — integración y validación

Proyecto: `/home/robin/1Devin/Projects/streams-roku`  
Fecha de generación: 2026-11-21 22:28:56 UTC  
Alcance: EPG de ahora/siguiente con XMLTV real. **No se implementó la rejilla EPG.**

> Nota de vigencia (2026-11-21): la generación local descrita aquí se conserva.
> La publicación de producción se migró a GitHub Actions + GitHub Pages. Ver
> `docs/DEPLOYMENT_GITHUB_PAGES.md`. El servidor local queda como herramienta de
> desarrollo, no como dependencia de producción.
## 1. Resumen

Se incorporó una fuente local real al pipeline:

- M3U snapshot de `robinpalat/streams` (51 canales).
- XMLTV generado con un checkout local de `iptv-org/epg`.
- Catálogo/EPG/coverage/manifiesto generados localmente.
- Sin publicación, hosting, GitHub Actions ni servicios externos.
- La app Roku no cambió: ya puede consumir los artefactos mediante la URL base
  de metadatos existente.

## 2. Auditoría inicial

Leídos: plan de integración vigente, `docs/IMPLEMENTACION_INFORME.md`,
`docs/VALIDACION_ROKU.md`, `pipeline/config/sources.json`, `pipeline/build.py`,
`pipeline/xmltv.py`, `pipeline/catalog.py`, `pipeline/grab_epg.py`,
`source/catalog.brs`, `source/epg.brs` y `components/MetadataTask.brs`.

Estado real de las fuentes:

| Fuente M3U | Canales | Con `tvg-id` | Nota |
|---|---:|---:|---|
| `robinpalat/streams` | 51 | 40 | Fuente principal para EPG |
| `m3u.cl/fav/Bulder.m3u` | 19 | 0 | Sin correspondencia directa; no se inventaron alias |
| `Mi PC` | — | — | No disponible en el entorno |

La correspondencia se resuelve exclusivamente por `tvg-id` (`canal@feed`) y
datos del catálogo. No se usaron coincidencias difusas de nombre.

## 3. Fuentes XMLTV reales

Se clonó localmente `iptv-org/epg` y se ejecutaron sus grabadores con archivos
`channels-*.xml` propios. Los archivos resultantes están en `pipeline/real/`.

| Sitio/grabador | Canales configurados | Resultado |
|---|---:|---|
| `mi.tv` | 6 | 5 con programas; Space se sustituyó por gatotv |
| `gatotv.com` | 3 | Cinecanal Pacífico, Historia y Space con programas |
| `i.mjh.nz` (Pluto/Plex/Roku) | 7 | 5 con programas; CinePride y Stingray sin programas desde este sitio; Stingray se cubrió con tv.nu |
| `teleboy.ch` | 2 | DW Español y TVE Internacional con programas |
| `tv.nu` | 1 | Stingray Classica con programas |
| `reportv.com.ar` | 1 | Eurochannel con programas |
| `distro.tv` | 1 | **Fallo DNS** (`getaddrinfo ENOTFOUND tv.jsrdn.com`); no se usó |

`CinePride.us@SD` permanece con 0 programas; no se inventó programación.
`Space.ar@Panregional` tiene datos de gatotv y se descartó la entrada vacía de
mi.tv mediante selección por mayor número de programas.

Comandos usados (desde el checkout local de `iptv-org/epg`):

```bash
npm run grab --- \
  --channels=/ruta/a/channels-mi.xml \
  --output=/ruta/a/guide-mi.xml \
  --days=1 --timeout=30000
```

Se repitió por grupo (`mi`, `gatotv`, `imjh`, `teleboy`, `extra`). El pipeline
deduplica por `channel id` eligiendo la fuente con más programas para evitar
programas duplicados o solapados.

## 4. Correspondencia y cobertura efectiva

El catálogo se construyó desde el `tvg-id` de la M3U y los snapshots locales de
`channels.json`, `feeds.json` y `logos.json` de iptv-org.

| Métrica | Valor |
|---|---:|
| Canales M3U | 51 |
| Canales con `tvg-id` | 40 |
| Canales mapeados en catálogo | 40 |
| Canales con programas | **17** |
| Canales sin programas | 23 |
| Canales sin identificador/no mapeados | 11 |
| Cobertura potencial de mapeo | 78,4% (40/51) |
| **Cobertura efectiva** | **33,3% (17/51)** |
| Entradas de canal en `epg.json` | 18 |
| Programas procesados en la ventana | 326 |
| Programas con duración desconocida | 0 |
| Cobertura parcial (`endKnown=false`) | 14 |

Canales con programas en la ventana: DW Español, Mega, BBC Drama, CDM
Internacional, Cine Friki, Cine Western, Cinecanal Pacífico, Historia, 13C,
Love Nature, Stingray Classica, América TV, Space, Crimen & Historia, Eurochannel,
TVE Internacional y 24 Horas.

Canales sin programas (23): Bio Bio TV, Bob Esponja, Bob Esponja Pantalones
Cuadrados, CBN Español, Cinemax Hits, CinePride, Cinevisión Canal 19, Cosmos TV
(HD y SD), TVE Internacional Europe HD, AMC Series Latin America, Aurora Media
Films, Celta TV, CHTV, Cultura 24, Sony Channel Argentina, UTV Chile, Xtrema
Acción, Xtrema Cartoons, Xtrema Cine Clásico, Xtrema Terror, Love Nature HD y
HBO 2 Latin America HD.

Correspondencias deliberadamente **no** realizadas:

- `TVEInternacionalEurope.es@HD` y `LoveNature.ca@HD`: no hay feed HD exacto en
  los archivos XMLTV; no se reutilizó el feed SD.
- `HBO2LatinAmerica.us@HD`: no se encontró una fila de sitio con ese `xmltv_id`.
- `CinePride.us@SD`: fuente `distro.tv` falló y las alternativas devolvieron 0
  programas; se conserva como canal sin programación.
- `m3u.cl`: no tiene `tvg-id`; no se hicieron asociaciones por nombre.

## 5. Ventana temporal

- `windowStart = generación - 6 h`.
- `windowEnd = generación + 24 h`.
- Se incluyen programas que solapan la ventana.
- Los programas con `start` y sin `stop` se conservan con duración desconocida;
  no se inventa el final ni se calcula progreso. En esta fuente real no hubo
  programas sin `stop`; la fixture automatizada sí los cubre.
- Las horas XMLTV se normalizan a epoch UTC y la app las muestra con
  `roDateTime.ToLocalTime()`.

## 6. Artefactos

Generados en `pipeline/out/real/`:

| Archivo | Bytes |
|---|---:|
| `latest.json` | 560 |
| `catalog.json` | 17.875 |
| `epg.json` | 89.976 |
| `coverage.json` | 7.316 |

`latest.json` generado el 2026-11-21 22:28:56 UTC, `refreshAfter` una hora
después. `coverage.json` incluye `sourceErrors` con el fallo de `distro.tv`.
No se generaron shards porque el EPG no supera el umbral de 400 KB.

## 7. Arquitectura final

```text
pipeline/real/streams.m3u + guide-*.xml + channels-*.xml
  -> pipeline.build (por fuente)
     -> catalog.json (tvg-id + API snapshots locales)
     -> epg.json (ventana 24h+6h, deduplicado por canal)
     -> coverage.json (efectiva, sourceErrors)
     -> latest.json (versiones/hashes)
  -> pipeline.serve local (sin publicar)
  -> MetadataTask (Roku)
  -> MainScene / tarjeta ahora-siguiente
```

No se modificó `PlayChannel()`, `StartPlayback()`, zapping, subtítulos,
favoritos ni navegación. La app sigue usando el mismo contrato de metadatos.

## 8. Pruebas ejecutadas

| Prueba | Resultado |
|---|---|
| `python3 -m unittest discover -s pipeline/tests` | 63 aprobadas, 0 fallidas |
| BRS (`tests/run_brs_tests.sh`) | 62 aserciones, 0 fallos, 6 pendientes |
| BrighterScript compile (`bsc`) | 0 errores |
| `pipeline.validate --out pipeline/out/real` | OK |
| Servidor local real (`latest/catalog/epg/coverage`) | HTTP 200 |
| Build real repetido con el mismo `--now` | hashes idénticos |
| XMLTV real | 18 canales, 326 programas, cobertura 17/51 |
| Deduplicación por canal | Space/Stingray/CinePride resueltos sin duplicados |
| XMLTV sin `stop` | cubierto por fixtures, no por esta fuente real |

No se ejecutó la app en Roku físico en esta fase. No se declara PASS visual ni
de rendimiento en hardware.

## 9. Limitaciones y problemas pendientes

- Cobertura efectiva real: 33,3%; no es un objetivo garantizado.
- 23 canales mapeados no tienen programas en las fuentes elegidas.
- CinePride quedó sin programas; distro.tv falló por DNS.
- No se usaron feeds HD alternativos para TVE/Love Nature porque no son el mismo
  feed.
- La EPG de cada sitio tiene sus propios términos; los datos son locales y no se
  redistribuyen.
- Los programas se regeneraron con `--days=1`; para producción local se debe
  programar una ejecución periódica fuera de este proyecto.
- `MetadataTask` y la tarjeta EPG todavía requieren validación en Roku físico.
- La EPG se muestra en hora local del dispositivo, no en la zona del canal.
- No se implementó la rejilla EPG.

## 10. Archivos modificados/creados

### Creados

- `pipeline/real/streams.m3u`
- `pipeline/real/guide-mi.xml`
- `pipeline/real/guide-gatotv.xml`
- `pipeline/real/guide-imjh.xml`
- `pipeline/real/guide-teleboy.xml`
- `pipeline/real/guide-extra.xml`
- `pipeline/real/channels-mi.xml`
- `pipeline/real/channels-gatotv.xml`
- `pipeline/real/channels-imjh.xml`
- `pipeline/real/channels-teleboy.xml`
- `pipeline/real/channels-extra.xml`
- `pipeline/real/README.md`
- `pipeline/data/real/channels.json`
- `pipeline/data/real/feeds.json`
- `pipeline/data/real/logos.json`
- `pipeline/tests/test_real_epg.py`
- `docs/EPG_REAL_INFORME.md`

### Modificados

- `pipeline/config/sources.json`: fuente `real`.
- `pipeline/xmltv.py`: selección de una fuente por canal (mayor número de
  programas) para evitar duplicados.
- `pipeline/coverage.py`: `sourceErrors`.
- `pipeline/build.py`: pasa `errors` a coverage.
- `pipeline/README.md`: instrucciones de la fuente real.

No se modificó código Roku en esta fase.

## 11. Instrucciones exactas

Generar y validar:

```bash
cd /home/robin/1Devin/Projects/streams-roku
python3 -m pipeline.build --config pipeline/config/sources.json --source real --out pipeline/out
python3 -m pipeline.validate --out pipeline/out/real
```

Servir en local:

```bash
python3 -m pipeline.serve --dir pipeline/out --port 8000
```

En la app: **Fuentes** -> fuente real -> **FF** -> `http://IP-DEL-PC:8000/real/`.

Regenerar XMLTV (requiere un checkout local de `iptv-org/epg` y Node.js):

```bash
python3 -m pipeline.grab_epg \
  --epg-repo /tmp/opencode/iptv-org-epg \
  --channels pipeline/real/channels-mi.xml \
  --out pipeline/real/guide-mi.xml --days 1
```

Repetir para `channels-gatotv.xml`, `channels-imjh.xml`, `channels-teleboy.xml`
y `channels-extra.xml`, y regenerar los artefactos.

## 12. Validación física pendiente

- Que `MetadataTask` descargue el manifiesto real y muestre la tarjeta en Roku.
- Que los horarios se muestren correctamente en la zona local del dispositivo.
- Que el progreso avance solo en canales con `stop` conocido.
- Que un canal sin programas (CinePride) muestre “Sin información”.
- Que una actualización de EPG no reconstruya la lista ni interrumpa vídeo.
- Memoria/tiempo de parseo del `epg.json` real (89.976 bytes) en hardware.
