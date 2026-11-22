# Pipeline de catálogo, logos y EPG

El pipeline se puede ejecutar en local para desarrollo y alimenta el workflow de
GitHub Actions que publica la EPG en GitHub Pages. Ver
`docs/DEPLOYMENT_GITHUB_PAGES.md`.

El generador, la asociación por `tvg-id` y la ventana temporal no cambiaron. La
publicación solo incluye los JSON compactos; no publica M3U, streams, XMLTV ni
configuración local.

## Requisitos

- Python 3.11 o superior; usa únicamente la biblioteca estándar.
- Opcional: Node.js + [`iptv-org/epg`](https://github.com/iptv-org/epg) para generar XMLTV real.
- Las pruebas BrightScript requieren el intérprete `brs` (solo desarrollo):
  `npm install --prefix tests/brs`.

## Configuración

Edita `pipeline/config/sources.json`. Cada fuente puede incluir:

```json
{
  "id": "fixture",
  "name": "Fuente local",
  "m3u": "../fixtures/streams.m3u",
  "epg": ["../fixtures/guide.xml"],
  "data": {
    "channels": "../fixtures/api/channels.json",
    "feeds": "../fixtures/api/feeds.json",
    "logos": "../fixtures/api/logos.json",
    "aliases": "../fixtures/aliases.json"
  },
  "failed": []
}
```

- `m3u` puede ser una ruta local o una URL HTTP/HTTPS.
- `epg` acepta uno o varios XMLTV locales. Para producir XMLTV real, ejecuta los grabadores de `iptv-org/epg` fuera de este pipeline y apunta aquí a su salida.

Grabador local opcional (requiere un checkout de `iptv-org/epg` y Node.js):

```bash
python3 -m pipeline.grab_epg \
  --epg-repo /ruta/a/epg \
  --sites mi.tv,gatotv.com \
  --out pipeline/fixtures/generated/guide.xml \
  --days 2
```

Después añade ese XMLTV a `epg` en `sources.json`. No se publica ni se programa automáticamente.
- `data` son snapshots locales de la API de iptv-org; son opcionales.
- `aliases.logos` permite asociar un `tvg-id` a un logo revisado manualmente.

## Fuente real incluida

`pipeline/config/sources.json` incluye la fuente `real`, basada en el snapshot
`pipeline/real/streams.m3u` y en guías XMLTV locales de `mi.tv`, `gatotv.com`,
`i.mjh.nz`, `teleboy.ch`, `tv.nu` y `reportv.com.ar`. Los datos son locales y no
se publican; revisar términos de cada sitio antes de redistribuirlos.

Genera solo esa fuente con:

```bash
python3 -m pipeline.build --source real --out pipeline/out
python3 -m pipeline.validate --out pipeline/out/real
```

## Generar artefactos

```bash
python3 -m pipeline.build \
  --config pipeline/config/sources.json \
  --out pipeline/out \
  --now 2026-11-21T06:00:00Z
```

Genera por fuente:

- `latest.json`
- `catalog.json`
- `epg.json` o shards `epg_<grupo>.json` si el tamaño supera `--shard-threshold`
- `coverage.json`

La ventana EPG es `[now - 6h, now + 24h]`. Los programas sin `stop` cuentan como programación con duración desconocida.

## Validar

```bash
python3 -m pipeline.validate --out pipeline/out/fixture
```

## Servir en local para el Roku

```bash
python3 -m pipeline.serve --dir pipeline/out --port 8000
```

En la app, abre **Fuentes**, enfoca la fuente y pulsa **FF** para configurar la URL base de metadatos:
`http://<IP-del-PC>:8000/fixture/`.

El Roku descargará `latest.json`; solo bajará `catalog.json`/`epg.json` si la versión cambia, falta la caché o está corrupta.

## Pruebas

```bash
python3 -m unittest discover -s pipeline/tests -v
BRS=tests/brs/node_modules/.bin/brs tests/run_brs_tests.sh
```

Las pruebas de `brs` cubren validación, hash, diff, anomalías, identidad, logos y EPG. Las pruebas que requieren red real, `roUrlTransfer`, `cachefs` o un dispositivo Roku se marcan como pendientes de hardware/simulación.

## Spike de listas y geometría

La preparación y el procedimiento están en `docs/SPIKE_LABELLIST.md`. No hay
dispositivo Roku en este entorno, por lo que el spike queda pendiente de
validación física; no se declara aprobado.

## Licencias

No se descargan ni redistribuyen logos de tv-logos. `tvg-logo` y `logos.json` se usan como referencias; antes de distribuir cualquier imagen se debe verificar su licencia. La EPG de cada sitio también requiere revisión de términos.

## Servidor local de desarrollo

El servidor local es opcional y solo para desarrollo. La configuración central
está en `pipeline/config/roku.json` (host vacío = detección automática de la IPv4
LAN, puerto 8001, ruta `/real/`). El perfil de desarrollo crea:

- `pipeline/config/roku.generated.json`
- `source/app_config.brs` (URL usada por la app; no editar a mano)
- `pipeline/server/roku-epg.service.generated`

Instalar y arrancar el servicio de usuario:

```bash
bash pipeline/server/install.sh
bash pipeline/server/status.sh
bash pipeline/server/healthcheck.sh
```

Detener/arrancar:

```bash
systemctl --user stop roku-epg.service
systemctl --user start roku-epg.service
journalctl --user -u roku-epg.service -f
tail -f ~/.local/state/streams-roku/epg-server.log
```

El servidor escucha en `0.0.0.0:8001` y sirve `pipeline/out/`; el puerto 8000 no
se toca. Si se quiere arranque sin login, habilitar linger:
`sudo loginctl enable-linger "$USER"` (requiere autorización administrativa).

## IP y paquete Roku

Si cambia la IP del Debian:

```bash
python3 -m pipeline.configure
# opcional: bash pipeline/server/install.sh (si cambió el puerto)
# regenerar/reinstalar streams-roku.zip
```

La app migra automáticamente las fuentes existentes cuyo URL contiene
`robinpalat/streams` añadiendo el campo `meta` generado. En producción también
reemplaza un `meta` LAN antiguo por la URL HTTPS de GitHub Pages. No hay que
escribir IP, puerto ni URL con el mando.

Producción:

```bash
python3 -m pipeline.configure --profile production   --repo-url https://github.com/robinpalat/streams-roku.git
```

## Grilla EPG

En la app: **Playlist** -> `Guía EPG` -> OK. Navegación: arriba/abajo canales,
izquierda/derecha programas/ventana temporal, OK detalle, Back volver. La grilla
solo pinta 8 canales y una ventana de 4 h por vez; no procesa XMLTV en Roku.
