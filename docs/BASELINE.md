# Línea base (Fase 0)

Fecha: 2026-11-21

## Estado inicial del repositorio

- App Roku SceneGraph/BrightScript.
- Archivos originales: `manifest`, `source/main.brs`, `source/util.brs`,
  `components/MainScene.xml/.brs`, `components/PlaylistTask.xml/.brs`, `images/`.
- Sin tests, CI, package.json ni scripts de build.
- Reproducción en `PlayChannel()`/`StartPlayback()`; zapping en `Zap()`/`ZapList()`;
  favoritos en el registro; caché M3U en `cachefs:/pl_<id>.m3u`.
- El parser original descartaba `tvg-id`, `tvg-logo` y `tvg-name`.

## Contratos protegidos

No se cambiaron durante la implementación:

- `PlayChannel()` y `StartPlayback()`.
- `Zap()` y `ZapList()`.
- `m.current`, `m.playingUrl`, `m.video`, `content.url`, `streamFormat`.
- Subtítulos y reintentos.
- Navegación, pestañas, filtros y favoritos existentes.
- Persistencia de fuentes y último canal.

## Fuentes medidas

| Fuente | Canales | tvg-id | tvg-logo | Resultado |
|---|---:|---:|---:|---|
| `robinpalat/streams` | 51 | 40 | 40 | Válida |
| `m3u.cl/fav/Bulder.m3u` | 19 | 0 | 19 | Válida (requiere User-Agent de cliente) |
| `Mi PC` (`192.168.1.7:8000`) | — | — | — | No disponible durante la auditoría |

Estas cifras se obtuvieron con el parser local del pipeline y coinciden con la
auditoría documental. No son resultados de reproducción en hardware.

## Limitaciones iniciales observadas

- `PlaylistTask` no tenía TTL, ETag, hash, validación ni detección de anomalías.
- `onPlaylist()` reemplazaba la lista y llamaba a `RenderList()` sin reconciliar foco.
- `cachefs` es evictable; el registro tiene 32 KB.
- No hay dispositivo Roku disponible en este entorno. Las pruebas que dependen de
  `MarkupList`/`ChannelItem`, `Video`, `roUrlTransfer` real o `cachefs` quedan pendientes de
  validación física, salvo simulación/compilación estática.

## Pruebas de línea base creadas

- `pipeline/tests/test_m3u.py`
- `pipeline/tests/test_epg.py`
- `pipeline/tests/test_build.py`
- `tests/brs/m3u_update_test.brs`

Comandos:

```bash
python3 -m unittest discover -s pipeline/tests -v
BRS=tests/brs/node_modules/.bin/brs tests/run_brs_tests.sh
/tmp/opencode/bsc/node_modules/.bin/bsc --create-package false --diagnostic-level error
```

El compilador BrighterScript se usó como validación estática; no se distribuye
con la app.
