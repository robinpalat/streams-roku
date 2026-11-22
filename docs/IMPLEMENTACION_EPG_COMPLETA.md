# Implementación EPG completa — servidor, automática y grilla

Proyecto: `/home/robin/1Devin/Projects/streams-roku`  
Fecha: 2026-11-21  
Alcance: EPG real automática, servidor local persistente y grilla navegable.
No se realizaron commits ni publicación externa.

> Nota de vigencia (2026-11-21): la generación local descrita aquí se conserva.
> La publicación de producción se migró a GitHub Actions + GitHub Pages. Ver
> `docs/DEPLOYMENT_GITHUB_PAGES.md`. El servidor local queda como herramienta de
> desarrollo, no como dependencia de producción.
## 1. Resumen

Se completó el recorrido EPG:

```text
XMLTV real -> pipeline/out/real -> servidor 8001
  -> latest/catalog/epg/coverage -> MetadataTask
  -> caché -> asociación tvg-id -> tarjeta ahora/siguiente y grilla
```

La app ya no requiere introducir ninguna URL con el mando. La URL se genera desde
`pipeline/config/roku.json`, se escribe en `source/app_config.brs` y se migra
automáticamente en las fuentes existentes que coinciden con `robinpalat/streams`.

## 2. Servidor local persistente

- Servicio systemd de usuario: `roku-epg.service`.
- Estado observado: `enabled` y `active`.
- Bind: `0.0.0.0:8001` (LAN, no localhost).
- Sirve: `/home/robin/1Devin/Projects/streams-roku/pipeline/out`.
- Artefactos reales: `/real/`.
- Log: `~/.local/state/streams-roku/epg-server.log`.
- Healthcheck: `pipeline/server/healthcheck.sh`.
- El puerto 8000 sigue sirviendo el contenido de películas y no fue modificado.
- El instalador detiene únicamente un `pipeline.serve` previo en el puerto
  configurado; si el puerto está ocupado por otro proceso, aborta.

Instalación/reinstalación:

```bash
bash pipeline/server/install.sh
bash pipeline/server/status.sh
bash pipeline/server/healthcheck.sh
bash pipeline/server/smoke_test.sh
```

Detener/arrancar/logs:

```bash
systemctl --user stop roku-epg.service
systemctl --user start roku-epg.service
systemctl --user restart roku-epg.service
journalctl --user -u roku-epg.service -f
tail -f ~/.local/state/streams-roku/epg-server.log
```

Si se desea arranque sin inicio de sesión, se puede habilitar linger
(`sudo loginctl enable-linger "$USER"`); no se ejecutó por requerir autorización
administrativa.

### Configuración centralizada

`pipeline/config/roku.json`:

```json
{
  "host": "",
  "port": 8001,
  "metaPath": "/real/",
  "sourceMatch": "robinpalat/streams",
  "artifactsDir": "pipeline/out"
}
```

`host` vacío activa detección de IPv4 LAN. `pipeline/configure.py` genera:

- `pipeline/config/roku.generated.json`
- `source/app_config.brs`
- `pipeline/server/roku-epg.service.generated`

Dirección detectada en esta ejecución: `192.168.1.7`, puerto `8001`,
`http://192.168.1.7:8001/real/`.

Si cambia la IP:

```bash
python3 -m pipeline.configure
bash pipeline/server/install.sh
# regenerar/reinstalar streams-roku.zip
```

No hay IP/puerto repetidos en la lógica de la app: solo en los archivos generados
y en la URL M3U histórica de la fuente `Mi PC`, que se conserva por compatibilidad.

## 3. Configuración automática en Roku

- `source/app_config.brs` expone `DefaultMetaBase()` y
  `DefaultMetaSourceMatch()`.
- `LoadSources()` migra las fuentes existentes: si la URL contiene
  `robinpalat/streams` y no tiene `meta`, añade la base generada y guarda
  `sources` una vez.
- `MetaBase()` usa, por orden: `src.meta`, `meta_<id>` en registro, la base
  automática para la fuente real y `meta_base` como override avanzado.
- No se cambia la URL M3U, el id de fuente, los favoritos ni los canales.
- El usuario no necesita pulsar FF ni escribir nada.

La app se actualizó a `build_version=18`.

## 4. Integración EPG real

- `MetadataTask` consulta `latest.json` y descarga catálogo/EPG solo si cambia la
  versión o falta/está corrupta la caché.
- `tvg-id` es la clave de asociación; no hay fuzzy matching por nombre.
- La ventana sigue siendo 24 h + 6 h de margen.
- Programas con `start` y sin `stop` se mantienen con duración desconocida; no se
  calcula progreso sin `stop`.
- Los canales sin EPG muestran “Sin información de programación”.
- La actualización no toca `PlayChannel`, `StartPlayback`, `Zap`, `m.current`,
  `m.playingUrl`, `m.video` ni `content.url`.

Datos reales disponibles tras el diagnóstico: 17/51 canales con programas
(33,3%), 326 programas, 18 entradas de canal EPG (CinePride con 0 programas).

## 5. Tarjeta ahora/siguiente

La tarjeta existente se conserva y consume `m.epg`:

- nombre/logo/grupo del canal;
- programa actual y siguiente;
- horas locales de inicio/fin;
- descripción/categoría/episodio;
- barra de progreso solo si hay `start` y `stop`;
- estados vacío/agotado/cargando.

Se actualiza cada 30 s sin red y no descarga por cada cambio de foco.

## 6. Grilla EPG

Componente nuevo: `components/EpgGrid.xml/.brs`.

- Eje vertical: canales; horizontal: ventana de 4 h.
- 8 filas visibles; bloques proporcionales a la duración real.
- Línea vertical “Ahora” cuando el instante cae en la ventana.
- Logo/nombre del canal, bloques actuales/futuros seleccionados y detalle inferior.
- Canales sin programación: bloque “Sin programación”.
- Ventana navegable con Left/Right; canales con Up/Down.
- OK (o Play) muestra/actualiza la información del programa.
- Back cierra la grilla y vuelve al panel.
- Solo se crean nodos para la ventana visible; se limpian/regeneran con
  `removeChildrenIndex`, evitando mantener toda la EPG en SceneGraph.
- No procesa XMLTV en el dispositivo; usa el JSON compacto.

Acceso: en la lista Playlist aparece la fila **“Guía EPG”**; OK la abre. No se
usan botones numéricos ni una URL manual.

## 7. Archivos modificados/creados

### Creados

- `source/app_config.brs` (generado)
- `source/logo_geometry.brs`
- `components/EpgGrid.xml`
- `components/EpgGrid.brs`
- `pipeline/configure.py`
- `pipeline/config/roku.json`
- `pipeline/config/roku.generated.json` (generado)
- `pipeline/server/install.sh`
- `pipeline/server/healthcheck.sh`
- `pipeline/server/status.sh`
- `pipeline/server/smoke_test.sh`
- `pipeline/server/roku-epg.service.generated`
- `pipeline/tests/test_app_config.py`
- `docs/IMPLEMENTACION_EPG_COMPLETA.md`

### Modificados

- `manifest` (`build_version=18`)
- `source/util.brs` (migración automática de `meta`)
- `components/MainScene.xml` (EpgGrid, app_config)
- `components/MainScene.brs` (meta automática, guía, cierre, actualización de grilla)
- `components/PlaylistTask.xml`, `MetadataTask.xml`, `EpgGrid.xml` (incluyen app_config)
- `pipeline/README.md`
- `docs/VALIDACION_ROKU.md`

### Relacionados con la fase EPG real ya existente

- `pipeline/real/*` y `pipeline/data/real/*` (XMLTV y snapshots reales locales).
- `pipeline/xmltv.py` (selección de una fuente por canal).
- `pipeline/coverage.py` (`sourceErrors`).

## 8. Decisiones de diseño

- **MetadataTask separado de PlaylistTask:** una actualización de EPG no descarga
  la M3U ni reinicia MainScene.
- **MarkupList/ChannelItem para canales:** geometría de logos ya validada.
- **Grilla custom en Group:** 8 canales × 4 h, sin dependencias ni XMLTV en el
  dispositivo; solo nodos visibles.
- **Consulta de manifiesto separada de descarga:** no se descargan artefactos si
  la versión no cambia.
- **Cachefs evictable:** si falla, se reconstruye desde servidor; el reproductor
  no depende de EPG.
- **Sin grilla en Rich UI compleja:** se evita RowList horizontal con columnas
  desalineadas; la geometría temporal es explícita.

## 9. Pruebas ejecutadas

| Prueba | Resultado |
|---|---|
| `python3 -m unittest discover -s pipeline/tests` | 64 aprobadas, 0 fallidas |
| BRS (`tests/run_brs_tests.sh`) | 62 aprobadas, 0 fallidas, 6 pendientes de hardware |
| BrighterScript compile | 0 errores |
| Paquete Roku | 29 archivos, 2.031.727 bytes |
| `systemctl --user is-active roku-epg.service` | active |
| `systemctl --user is-enabled ...` | enabled |
| Healthcheck 8001 | OK |
| Smoke test HTTP (latest/catalog/epg/coverage) | 200, `application/json`, JSON válido |
| Puerto 8000 | Sigue sirviendo películas; intacto |
| Configuración de producción | `https://robinpalat.github.io/streams-roku/real/` |
| Hash del paquete | `22c4345440d37921586078dfb519780426500d764a5666969d2f29d5da830e0e` |

Las pruebas físicas de Roku **no se ejecutaron** en esta fase; no se declaran
aprobadas.

## 10. Limitaciones y pendientes

- La app debe reinstallarse con `streams-roku.zip`; el instalador de Roku pide
  credenciales de desarrollador, que no se solicitaron.
- La grilla y la tarjeta requieren validación visual/real en el Roku Express.
- Cobertura EPG real 33,3%; 23 canales sin programas y 11 sin `tvg-id`.
- CinePride sin programación; distro.tv falló por DNS.
- La UI de metadatos manual por FF no se corrigió porque la EPG ya no depende de
  ella; sigue disponible como override avanzado, no como requisito.
- El arranque del servicio de usuario requiere sesión; para arranque sin login
  se debe habilitar linger con autorización administrativa.
- Si cambia la IP, hay que regenerar y reinstalar el paquete.
- No se implementó ninguna base de datos ni servicio externo.

## 11. Instalación exacta

1. Verificar servidor:

```bash
cd /home/robin/1Devin/Projects/streams-roku
bash pipeline/server/install.sh
bash pipeline/server/status.sh
bash pipeline/server/smoke_test.sh
```

2. Instalar el paquete final en el Roku mediante el instalador de desarrollo
   (requiere la contraseña de developer mode del usuario):

```text
streams-roku.zip
```

No hay que introducir ninguna URL en la app.

3. Abrir la app. La primera ejecución migra `sources` y añade `meta` a la fuente
   `robinpalat/streams` automáticamente.

4. Abrir panel con Back; en Playlist aparecerá **Guía EPG** como primera fila.
   Pulsar OK para abrir la grilla.

## 12. Prueba física consolidada

1. Abrir la app desde Home y esperar la lista.
2. Abrir panel con Back; comprobar que **Guía EPG** aparece.
3. Enfocar un canal con EPG (Mega, 13C, 24 Horas, DW Español) y comprobar tarjeta
   ahora/siguiente.
4. Abrir **Guía EPG** con OK.
5. Up/Down por canales; Left/Right por programas/tiempo.
6. OK sobre un programa; comprobar título, horas y descripción.
7. Enfocar CinePride o un canal sin EPG; comprobar “Sin programación”.
8. Back; comprobar regreso al panel y reproducción intacta.
9. Reproducir un canal, abrir/cerrar grilla; el vídeo y `m.playingUrl` deben
   continuar.
10. Reiniciar app; comprobar que EPG se recupera desde servidor/caché.

Si falla, recoger: ID de paso, modelo/OS, estado en pantalla, `telnet ROKU_IP 8085`,
`systemctl --user status`, log del servidor y artefacto solicitado.

## 13. Verificación de que no se tocó el reproductor

La grilla y la configuración automática no modifican `PlayChannel`,
`StartPlayback`, `Zap`, `m.current`, `m.playingUrl`, `m.video`, `content.url`,
`streamFormat`, subtítulos, reintentos, favoritos ni navegación existente. La
única fila nueva es `Guía EPG`; la EPG se actualiza en tareas separadas.
