# Plan de integración de logos y EPG en la aplicación Roku

**Proyecto auditado:** `/home/robin/1Devin/Projects/streams-roku`  
**Fecha de auditoría:** 2026-11-21  
**Revisión:** segunda auditoría técnica + ampliación de actualización dinámica de M3U + correcciones puntuales, 2026-11-21  
**Alcance:** auditoría, diagnóstico y plan técnico. No se ha implementado ningún cambio.  
**Estado:** propuesta revisada, pendiente de autorización expresa.

## Convenciones de evidencia

Este documento distingue explícitamente:

- **[HECHO]**: comprobado directamente en el código local, con ruta y línea.
- **[VERIFICADO]**: comprobado en documentación o repositorios externos en la fecha de auditoría.
- **[HIPÓTESIS]**: inferencia técnica razonable, todavía no probada en dispositivo.
- **[PENDIENTE]**: decisión, dato o validación que falta y que puede cambiar el plan.

No se han inventado archivos, funciones ni capacidades. Cuando una característica externa no se ha podido verificar, se indica.

---

## 1. Resumen ejecutivo

La aplicación es una app Roku SceneGraph/BrightScript pequeña y funcional que carga listas M3U, muestra canales agrupados por `group-title`, reproduce streams y guarda favoritos, fuentes y último canal en el registro de Roku. La reproducción, la navegación y el manejo de subtítulos están concentrados en `components/MainScene.brs` y no deben modificarse para incorporar logos o EPG.

Conclusiones principales:

1. **Los logos se pueden incorporar con bajo riesgo sin cambiar el nodo de lista.** El nodo `LabelList` usado en `components/MainScene.xml:14` admite iconos por elemento mediante los atributos `HDListItemIconURL` y `HDListItemIconSelectedURL` **[VERIFICADO]**. Además, las listas M3U de iptv-org ya traen `tvg-logo` y la fuente por defecto de la app incluye logo en 40 de sus 51 canales **[VERIFICADO]**. La primera fase puede usar ese dato directamente, con imagen de reserva y sin tocar la reproducción.
2. **La EPG no debe procesarse en el dispositivo.** `guides.json` de iptv-org pesa 25,6 MB y contiene 180.680 filas **[VERIFICADO]**; `channels.json` pesa 8,0 MB y `logos.json` 5,8 MB. Un XMLTV completo puede ser mucho mayor. Procesar esos volúmenes en BrightScript, con la memoria y el almacenamiento de un Roku, es inviable. La arquitectura correcta es un proceso externo que genere un JSON compacto por fuente y que el Roku descargue en segundo plano.
3. **El identificador de unión fiable es `tvg-id` = `channel@feed`, no el nombre.** En las listas de iptv-org, `tvg-id` tiene la forma `DW.de@Espanol`, `Mega.cl@SD`, etc. **[VERIFICADO]**. La EPG de iptv-org usa `xmltv_id` con la misma forma (`Channel9.il@SD`, `AlJazeera.qa@English`) **[VERIFICADO]**, y su salida XMLTV usa `<channel id="Channel1.us@HD">` **[VERIFICADO]**. Por tanto, para listas basadas en iptv-org existe una correspondencia directa y estable.
4. **La cobertura de EPG potencial es parcial y la efectiva aún no se ha medido.** De los 40 canales con `tvg-id` de la fuente por defecto `robinpalat/streams`, 21 tienen alguna fila de guía y 19 tienen coincidencia exacta canal+feed en `guides.json` **[VERIFICADO]**. Esos valores son **cobertura potencial de mapeo**, no cobertura efectiva: que exista una fila no garantiza que el grabador funcione ni que devuelva programas. La fuente `m3u.cl` no incluye `tvg-id` en sus 19 canales **[VERIFICADO]**, por lo que no tiene mapeo directo; esto no demuestra que esos canales carezcan de EPG, ya que podrían asociarse mediante alias manuales. La cobertura efectiva debe medirse ejecutando los grabadores y registrando canales con programas, sin programas y fallidos.
5. **No se deben empaquetar logos ni EPG dentro de la app.** El paquete ya contiene ~1,9 MB de imágenes **[HECHO]**. Roku limita el tamaño del paquete (4 MB según foro oficial de Roku; conviene validar el límite vigente) **[PENDIENTE]**. Los datos deben servirse desde un host estático o desde el servidor local que el usuario ya utiliza como fuente.
6. **La EPG debe cubrir una ventana móvil de al menos 24 horas**, no dos programas. El JSON debe incluir todos los programas que solapen esa ventana, con un instante de refresco separado de la generación, la publicación, la descarga y el refresco visual.
7. **Las listas M3U públicas son dinámicas y requieren un mecanismo propio.** El `PlaylistTask` actual guarda una copia y la usa como fallback, pero no tiene TTL, ETag ni validación de contenido **[HECHO]**. Se propone una actualización *cache-first* con revalidación condicional, validación, cuarentena de anomalías, última versión válida y reconciliación segura de foco/sesión, sin tocar la reproducción (sección 15).
8. **La recomendación es por fases:** primero modelo y logos; en paralelo o antes de EPG, actualización dinámica de M3U; después EPG con ventana de 24 h; después caché y actualización; la rejilla EPG completa queda como evaluación opcional y probablemente deba ser paginada, no una parrilla global.

**Decisión recomendada:** aprobar Fase 1 y el spike de la Fase 2a; continuar la Fase 2 solo si el spike nativo pasa las puertas. No aprobar la Fase 3 hasta medir la cobertura efectiva, validar el payload de 24 h y confirmar el hosting y las licencias. No prometer una EPG completa.

---

## 2. Diagnóstico de la arquitectura actual

### 2.1 Stack y estructura

| Elemento | Evidencia | Valor |
|---|---|---|
| Plataforma | `manifest` | Roku SceneGraph + BrightScript |
| Resolución UI | `manifest:5` | `ui_resolutions=hd` |
| Versión | `manifest:2-4` | 1.0, build 12 |
| Arranque | `source/main.brs:1` | `roSGScreen`, `MainScene`, `roInput` |
| Escena principal | `components/MainScene.xml:2` | extiende `Scene` |
| Tarea de red | `components/PlaylistTask.xml:2` | extiende `Task` |
| Utilidades | `source/util.brs` | registro, fuentes, formato, nombres |
| Imágenes | `images/` | iconos y splash; no hay logos de canales |
| Pruebas | — | **No hay tests, CI, package.json ni scripts de build** **[HECHO]** |

### 2.2 Flujo de datos actual

```
Main (source/main.brs)
  -> MainScene
       -> LoadSources() / LoadFavs() (source/util.brs)
       -> PlaylistTask.fetchPlaylist() (roUrlTransfer + cachefs)
            -> ParseM3U() -> [{kind, name, group, url, subs}]
       -> onPlaylist() -> RenderList() (LabelList)
       -> onItemSelected() -> PlayChannel() -> StartPlayback() (Video)
```

- El parser M3U está en `components/PlaylistTask.brs:59-86`.
- La lista visual se construye en `components/MainScene.brs:140-200` y se asigna a `m.list.content` en `MainScene.brs:186`.
- La reproducción empieza en `PlayChannel()` (`MainScene.brs:291`) y `StartPlayback()` (`MainScene.brs:312`).
- La navegación por mando está en `onKeyEvent()` (`MainScene.brs:581-662`).
- El zapping usa favoritos y el último canal temporal (`ZapList()`, `MainScene.brs:426`; `Zap()`, `MainScene.brs:448`).

### 2.3 Modelo de datos actual de canal

Cada canal se representa como un `roAssociativeArray` **[HECHO]**:

```brightscript
{ kind: "ch", name: name, group: group, url: l, subs: subs }
```

Fuente: `components/PlaylistTask.brs:77`.

Los favoritos añaden `src` (`MainScene.brs:267`) y conservan los mismos campos. El último canal se guarda por URL en el registro (`MainScene.brs:307`).

**Limitación clave:** el parser obtiene `group-title` y `subtitles` con `GetAttr()` (`PlaylistTask.brs:36-44`), pero **descarta `tvg-id`, `tvg-logo` y `tvg-name`** **[HECHO]**. La función `GetAttr` ya es reutilizable para incorporarlos.

### 2.4 Carga y caché de listas M3U

- `PlaylistTask.fetchPlaylist()` descarga con `roUrlTransfer.GetToString()` dentro de una tarea (`PlaylistTask.brs:10-14`).
- Si la respuesta parece M3U, escribe `cachefs:/pl_<id>.m3u` (`PlaylistTask.brs:7,16-18`).
- Si falla, lee la copia cacheada (`PlaylistTask.brs:19-24`).
- No hay TTL, ETag, `If-None-Match`, ni revalidación condicional **[HECHO]**.
- El estado se devuelve en `m.top.result` (`PlaylistTask.brs:28-33`).

**Limitación crítica:** esta protección solo cubre el caso de red caída. No detecta cambios de contenido, listas truncadas, HTML de error, listas vacías ni caídas bruscas de canales. Además, `onPlaylist()` reemplaza `m.channels` y llama a `RenderList()` sin reconciliar foco ni sesión (`MainScene.brs:87-104,140-200`), por lo que una actualización podría reconstruir la interfaz o alterar la navegación. La arquitectura específica para fuentes dinámicas se desarrolla en la **sección 15**.

### 2.5 Persistencia

`source/util.brs:1-11` implementa `RegRead`/`RegWrite` sobre `roRegistrySection("streams")`.

Claves actuales **[HECHO]**:

| Clave | Uso | Origen |
|---|---|---|
| `sources` | JSON de fuentes | `util.brs:23,50` |
| `favs` | JSON de favoritos | `util.brs:54,63` |
| `active` | Fuente activa | `MainScene.brs:32,237,568` |
| `last_<id>` | Última URL por fuente | `MainScene.brs:107,307` |
| `seeded_v2` | Migración de fuentes por defecto | `util.brs:35-44` |

**Límite verificado:** el registro de Roku tiene un máximo de 32 KB comprimidos por aplicación en la documentación oficial actual; documentación antigua citaba 16 KB **[VERIFICADO]**. Por tanto, el registro solo puede usarse para ajustes pequeños, nunca para EPG o catálogos.

### 2.6 Imágenes y HTTP

- Solo hay imágenes empaquetadas en `images/`: `icon_hd.png`, `icon_sd.png`, `splash_sd.png`, `splash_hd.png`, `splash_fhd.png` **[HECHO]**.
- No hay `Poster`, `LabelList` con iconos, ni caché de imágenes remotas **[HECHO]**.
- `roUrlTransfer` ya configura el bundle de certificados (`PlaylistTask.brs:11-12`), por lo que HTTPS funciona.
- No se configura `EnableEncodings(true)`, ni timeout, ni límite de transferencia **[HECHO]**.

### 2.7 Configuración de fuentes

`DefaultSources()` (`source/util.brs:13-19`) define tres fuentes:

1. `robinpalat/streams` (`streams.m3u`)
2. `Bulder (m3u.cl)` (`https://m3u.cl/fav/Bulder.m3u`)
3. `Mi PC (192.168.1.7)` (`http://192.168.1.7:8000/playlist.m3u`)

El usuario puede añadir una URL M3U manualmente (`MainScene.brs:233-234,562-577`). Cualquier solución debe funcionar también para fuentes arbitrarias, al menos de forma degradada.

### 2.8 Limitaciones y conductas relevantes

- La lista limita la vista a 2000 elementos (`MainScene.brs:157,422`) **[HECHO]**.
- Todo el array de canales se mantiene en memoria (`m.channels`) **[HECHO]**.
- El parser parte el `#EXTINF` por comas y toma el último fragmento como nombre (`PlaylistTask.brs:70-71`); nombres con comas pueden truncarse. Es una conducta existente que no debe cambiarse sin pruebas de regresión **[HECHO]**.
- No se soportan `http-user-agent` ni `http-referrer` de la M3U; algunas fuentes de iptv-org los incluyen **[VERIFICADO]**. No forma parte de este alcance, pero es un riesgo preexistente para ciertos canales.
- La app usa `WriteAsciiFile`/`ReadAsciiFile` para la caché M3U (`PlaylistTask.brs:17,19`). El tratamiento de UTF-8 debe validarse antes de reutilizarlo para EPG **[PENDIENTE]**.

---

## 3. Inventario de módulos relevantes

| Archivo | Función actual | Reutilización | Cambio previsto | Riesgo |
|---|---|---|---|---|
| `manifest` | Metadatos y splash | Directa | Posible `build_version`; no requiere dependencias | Bajo |
| `source/main.brs` | Arranque, entrada ECP | Directa | Ninguno | Nulo |
| `source/util.brs` | Registro, fuentes, favoritos, formatos | Alta | Añadir helpers de normalización y claves de caché | Bajo |
| `components/MainScene.xml` | Layout, `LabelList`, `Video`, timers | Alta | Añadir tarjeta EPG y timer de refresco; `itemSize` si se reserva columna | Medio |
| `components/MainScene.brs` | Navegación, render, reproducción | Alta | Añadir enriquecimiento de canales, iconos, EPG y observadores | **Alto si se toca playback** |
| `components/PlaylistTask.xml` | Interfaz de la tarea | Alta | Sin cambios o campos extra opcionales | Bajo |
| `components/PlaylistTask.brs` | Descarga y parseo M3U | Alta | Capturar `tvg-id`, `tvg-logo`, `tvg-name`; conservar campos actuales | Medio |
| `images/` | Splash e iconos | Directa | Añadir `logo_placeholder.png` empaquetado | Bajo |
| `PLAN_INTEGRACION_LOGOS_EPG(3).md` | Este plan | — | Documento nuevo | Nulo |

**No existen** componentes de detalle de canal, guía, metadatos, logos ni tareas de EPG. Serían nuevos.

### 3.1 Qué no debe modificarse

Para preservar el funcionamiento actual:

- `PlayChannel()` y `StartPlayback()` no deben cambiar de contrato ni de flujo.
- No cambiar `content.url`, `streamFormat`, subtítulos ni la lógica de reintentos (`ScheduleRetry`, `onVideoState`).
- No cambiar las teclas ni la navegación de pestañas.
- No eliminar `m.temp`, `ZapList`, búsqueda, carpetas ni favoritos.
- Mantener el esquema de favoritos existente; los campos nuevos deben ser opcionales.
- Mantener las fuentes por defecto y el resultado base de `PlaylistTask` (`id`, `status`, `items`, `n`); los campos nuevos son opcionales.
- La evolución de la caché M3U se define en la sección 15; no debe romper el fallback actual.

---

## 4. Análisis de las fuentes de datos

### 4.1 iptv-org/iptv y API de iptv-org

**Repositorio de listas:** `https://github.com/iptv-org/iptv`  
**API:** `https://github.com/iptv-org/api`

Hechos verificados el 2026-11-21:

- La lista principal `https://iptv-org.github.io/iptv/index.m3u` pesa **2.673.684 bytes** y tiene `last-modified: 2026-11-21 00:12:01 GMT` **[VERIFICADO]**.
- El formato es M3U con entradas como:

```text
#EXTINF:-1 tvg-id="DW.de@Espanol" tvg-logo="https://i.imgur.com/8MRNFb9.png" group-title="News",DW Espanol (1080p)
https://...
```

- `tvg-id` identifica **canal y feed**: `canal@feed`. Ejemplos observados: `00sReplay.us@SD`, `1Plus1International.ua@HD`, `DW.de@Espanol` **[VERIFICADO]**.
- Algunas entradas incluyen `http-user-agent`, `http-referrer`, `#EXTVLCOPT`, etiquetas como `[Not 24/7]`, y nombres con calidad `(1080p)` **[VERIFICADO]**.
- No todas las entradas tienen `tvg-id` ni `tvg-logo` **[VERIFICADO]**.

Endpoints y tamaños descargados:

| Endpoint | Tamaño | Registros | Campos relevantes |
|---|---:|---:|---|
| `https://iptv-org.github.io/api/channels.json` | 7.983.890 B | 31.797 | `id`, `name`, `alt_names`, `country`, `categories`, `replaced_by`, `closed` |
| `https://iptv-org.github.io/api/feeds.json` | — | 45.374 | `channel`, `id`, `name`, `is_main`, `timezones`, `languages`, `format` |
| `https://iptv-org.github.io/api/logos.json` | 5.788.125 B | 35.608 | `channel`, `feed`, `in_use`, `format`, `width`, `height`, `url` |
| `https://iptv-org.github.io/api/streams.json` | 3,9 MB aprox. | 19.420 | `channel`, `feed`, `url`, `referrer`, `user_agent`, `quality`, `labels` |
| `https://iptv-org.github.io/api/guides.json` | 25.620.127 B | 180.680 | `channel`, `feed`, `site`, `site_id`, `site_name`, `lang`, `sources` |

Datos adicionales de logos **[VERIFICADO]**:

- 35.608 registros de logo; 30.643 canales distintos con al menos un logo de 31.797 canales.
- Formatos: PNG 30.129, JPEG 3.805, SVG 1.358, WebP 278, GIF 4, AVIF 1, sin formato 33.
- Solo 14 URLs apuntan al repositorio `tv-logo/tv-logos`; la mayoría son `i.imgur.com` (24.524), Wikimedia (3.117) y Pluto TV (1.377).
- `in_use=true` en 35.108 registros; `false` en 500.
- Conclusión: **`logos.json` es una fuente de correspondencia mucho más fiable que los nombres de archivo de tv-logos**, porque incluye el `channel` de iptv-org y el `feed`.

Datos adicionales de guías **[VERIFICADO]**:

- 31.679 filas tienen `channel`; 31.445 tienen `feed`; 11.771 canales de 31.797 tienen alguna fila de guía.
- **Ninguna fila tenía `sources` no vacío en la fecha de auditoría** (0 de 180.680). Es decir, `guides.json` sirve para saber *qué sitio y qué `site_id`* corresponden a un canal, pero **no entrega una URL XMLTV lista para descargar**.
- 2.900 identificadores de canal de `guides.json` no existen en `channels.json`; pueden ser canales cerrados, renombrados o datos desactualizados.
- Idiomas principales: `en` 94.007, `fr` 18.735, `ar` 16.355, `es` 10.594.

**Implicación:** la EPG debe generarse ejecutando los grabadores de `iptv-org/epg` (o una fuente equivalente) en un proceso externo. No se puede depender de `guides.json` como catálogo de XMLTV descargables mientras `sources` siga vacío.

### 4.2 tv-logo/tv-logos

**Repositorio:** `https://github.com/tv-logo/tv-logos`

Hechos verificados:

- Contiene 10.852 archivos: 10.777 PNG y 73 Markdown (mosaicos por país); **no hay JSON ni CSV** con índice de correspondencias **[VERIFICADO]**.
- Estructura por país: `countries/chile/13c-cl.png`, `countries/spain/24h-es.png`, `countries/united-kingdom/...` **[VERIFICADO]**.
- Los nombres son normalizados: minúsculas, guiones por espacios, código de país al final, `plus` para diferidos, `and` para `&`, `hz` para versión horizontal **[VERIFICADO]**.
- Los logos son PNG de 512 px de ancho, pensados para fondo oscuro **[VERIFICADO]**.
- **No existe una correspondencia directa entre el nombre de archivo y el `id` de iptv-org.** Ejemplo: el canal `13C.cl` puede aparecer como `13c-cl.png`, pero no hay garantía sistemática.
- Licencia declarada en el README: CC BY-SA / CC BY-NC-SA, marcas registradas, y el autor pide contactar antes de enlazar los logos desde un servicio **[VERIFICADO]**. No hay archivo `LICENSE` en el árbol **[VERIFICADO]**.

**Conclusión:** tv-logos no debe ser la fuente principal de correspondencia automática. Es útil como fuente suplementaria para canales sin logo, mediante una tabla de alias revisada manualmente y respetando licencia/atribución.

### 4.3 iptv-org/epg

**Repositorio:** `https://github.com/iptv-org/epg`

Hechos verificados:

- Es una herramienta Node.js de grabbing, no un servicio de EPG listo para consumir. Se ejecuta con `npm run grab --- --sites=...` o `--channels=...` **[VERIFICADO]**.
- Opciones relevantes: `--sites`, `--channels`, `--output`, `--days`, `--gzip`, `--json`, `--timeout`, `--delay`, `--maxConnections` **[VERIFICADO]**.
- Salida por defecto: `guide.xml` en XMLTV. También puede generar `.gz` y JSON **[VERIFICADO]**.
- Formato de salida verificado en fixtures del propio repositorio:

```xml
<tv date="20221020">
  <channel id="Channel1.us@HD">
    <display-name>Channel 1</display-name>
    <icon src="..."/>
  </channel>
  <programme start="20221020043000 +0000" stop="20221020071000 +0000" channel="Channel1.us@HD">
    <title lang="en">Program1</title>
  </programme>
</tv>
```

- Las horas XMLTV son `YYYYMMDDhhmmss +ZZZZ`; en los ejemplos se usa `+0000` (UTC) **[VERIFICADO]**.
- Un `<programme>` puede no incluir `stop`. Si tiene `start` y título, sigue siendo programación encontrada; el generador no debe descartarlo ni asignarle una duración inventada. Ejemplo válido:

```xml
<programme start="20221020043000 +0000" channel="Channel1.us@HD">
  <title lang="en">Program with unknown duration</title>
</programme>
```
- Los archivos de canales por sitio usan `xmltv_id` con formato `canal@feed`; ejemplo verificado: `xmltv_id="Channel9.il@SD"` y `xmltv_id="AlJazeera.qa@English"` **[VERIFICADO]**.
- Si `xmltv_id` está vacío, el grabador usa `site_id` como identificador (`scripts/commands/epg/grab.ts:230`) **[VERIFICADO]**. Eso significa que no todos los canales tienen un ID iptv-org válido.
- El grabador separa el feed con `xmltv_id.split('@')[0]` para buscar metadatos (`grab.ts:350`) **[VERIFICADO]**.
- Actualización del repositorio: workflow diario a las 00:00 UTC (`cron: '0 0 * * *'`) **[VERIFICADO]**. La imagen Docker descarga la guía por defecto cada día a las 00:00 UTC **[VERIFICADO]**. La frecuencia efectiva del XMLTV depende de la programación que se configure.
- Licencia del repositorio: el archivo `LICENSE` es de dominio público (Unlicense/CC0), aunque `package.json` declara `UNLICENSED` **[VERIFICADO]**. La licencia del *contenido* de las guías de cada sitio debe revisarse por separado **[PENDIENTE]**.
- `guides.json` no contiene URLs de descarga (`sources` vacío) **[VERIFICADO]**.
- **Cobertura potencial de mapeo** para la fuente por defecto de la app: 21 de 40 canales con `tvg-id` tienen alguna fila; 19 tienen coincidencia exacta canal+feed **[VERIFICADO]**. No es cobertura efectiva.
- **Cobertura potencial de mapeo** de canales chilenos en `guides.json`: 35 canales, principalmente sitios `mi.tv` (29 filas) y `gatotv.com` (11 filas) **[VERIFICADO]**. Esto no garantiza que el grabador funcione hoy, que devuelva programas ni que esos sitios permitan redistribución.
- No se encontró un XMLTV global publicado por iptv-org en `https://iptv-org.github.io/epg/` (HTTP 404 en las rutas probadas) **[VERIFICADO]**.

**Conclusión:** la EPG requiere un pipeline propio (GitHub Actions, cron, Docker o servidor) que ejecute grabadores para el subconjunto de canales mapeados y publique JSON compacto. Los grabadores pueden fallar por cambios de sitio, geobloqueo o límites; la cobertura efectiva será menor que la potencial y debe medirse, no inferirse.

#### 4.3.1 Procedimiento para medir la cobertura efectiva

La cobertura efectiva no se deduce de `guides.json`. Debe medirse con una ejecución controlada de los grabadores:

1. Construir un `channels.xml` con únicamente los canales mapeados para la fuente auditada, incluyendo `site`, `site_id`, `lang` y `xmltv_id`.
2. Ejecutar el grabador por sitio con una ventana de prueba (`--days=2` o la máxima disponible) y capturar el log por canal:
   `npm run grab --- --channels=... --output=... --days=2`.
3. Parsear el XMLTV resultante y clasificar cada canal:
   - `mapeado_con_programas`: existe `<channel id="...">` y al menos un `<programme>` con `start` válido y título. **`stop` es opcional**; su ausencia no convierte al canal en “sin programación”.
   - `mapeado_con_duracion_desconocida`: subconjunto del anterior con al menos un programa con `start` válido y sin `stop`. Se registra por separado.
   - `mapeado_sin_programas`: existe el canal pero no hay ningún programa con `start` válido y título en la ventana.
   - `fallo_grabber`: el canal no aparece o el sitio devuelve error.
   - `no_mapeado`: no hay fila de guía ni alias aprobado.
4. Calcular y publicar:
   - cobertura potencial = canales mapeados / canales totales;
   - cobertura efectiva = canales con al menos un programa con `start` válido y título / canales totales;
   - tasa de éxito = canales con programas / canales mapeados;
   - `programas_sin_stop` y `canales_con_duracion_desconocida` como métricas separadas;
   - desglose por sitio, idioma y motivo de fallo.
5. Repetir al menos tres ejecuciones en días distintos para separar fallos transitorios de fallos estructurales.
6. Validar frescura y calidad: al menos un programa debe cubrir el instante de generación. Para programas sin `stop`, la cobertura se determina con el `start` y, si existe, con el `start` del siguiente programa; no se inventa un `stop` ni una duración. Sin duplicados, sin solapamientos no resueltos y sin huecos inexplicables.
7. Publicar un `coverage.json` con el detalle por canal. El porcentaje agregado no basta para decidir.

**Decisión pendiente:** la cobertura efectiva real solo se conocerá después de este procedimiento. Los 21/40 y 19/40 son el punto de partida potencial, no el resultado final. Los canales sin `tvg-id`, como los de `m3u.cl`, pueden incorporarse mediante alias manuales; no se declaran definitivamente sin EPG.

### 4.4 Resumen de fuentes

| Necesidad | Fuente primaria | Fuente secundaria | No usar en dispositivo |
|---|---|---|---|
| Identidad de canal | `tvg-id` de la M3U; `channels.json`/`feeds.json` para validar | `alt_names` | Cargas completas de API |
| Logo | `tvg-logo` de la M3U | `logos.json` por `channel`/`feed`; tv-logos con alias manual | Hotlinks sin normalizar |
| EPG | XMLTV generado con `iptv-org/epg` | Otra EPG con licencia | XMLTV completo |
| Metadatos de canal | `channels.json`, `feeds.json` | `guides.json` para descubrir sitios | `guides.json` completo |

---

## 5. Estrategia de correspondencia de canales

### 5.1 Principio

La correspondencia debe resolverse **fuera del dispositivo**: primero en el generador local de la Fase 1 y, cuando el hosting esté autorizado, en el pipeline de publicación. Debe quedar congelada en un catálogo compacto. El dispositivo no debe hacer fuzzy matching en tiempo de ejecución ni descargar tablas completas.

Prioridad de identificadores:

1. `tvg-id` exacto (`canal@feed`), validado contra `channels.json` y `feeds.json`.
2. `tvg-id` de canal sin feed, si el catálogo tiene una única guía principal.
3. `tvg-logo` como identidad visual, aunque no haya EPG.
4. Alias manual por URL o por nombre normalizado + país/grupo, con revisión.
5. Sin correspondencia: logo de reserva y “Sin EPG”.

### 5.2 Normalización de nombres (solo para candidatos, nunca para decidir sola)

Propuesta de normalización en el pipeline:

- Pasar a minúsculas.
- Quitar acentos y diacríticos.
- Quitar sufijos de calidad: `(1080p)`, `(720p)`, `(480p)`, `HD`, `SD`, `FHD`, `4K`.
- Quitar sufijos de país entre paréntesis solo si el país ya está en el grupo o en el catálogo.
- Normalizar `&`/`and`, `+`/`plus`, guiones, apóstrofos y espacios.
- Quitar marcas de la app: `[Not 24/7]`.
- Comparar contra `name` y `alt_names`.
- Exigir coincidencia única; si hay más de un candidato, no asignar automáticamente.
- Guardar `matchMethod` y `confidence` en el catálogo para auditoría.

### 5.3 Casos y resolución

| Caso | Ejemplo | Resolución |
|---|---|---|
| `tvg-id` + `tvg-logo` | `DW.de@Espanol` | Usar logo y EPG exactos; validar IDs en API |
| `tvg-id` sin logo | `X.us@SD` | Logo desde `logos.json`; si no, alias tv-logos; si no, reserva |
| `tvg-logo` sin `tvg-id` | Fuente `m3u.cl` | Mostrar logo; EPG solo mediante alias manual revisado; no se asume ausencia definitiva |
| Sin `tvg-id` ni logo | 11 canales de `robinpalat/streams` | Reserva; candidato por nombre solo si es único y revisado |
| Canal regional | `France3.fr@ParisIledeFrance` | Priorizar feed exacto; no usar el feed principal si la EPG es regional |
| Varias versiones | `LoveNature.ca@SD` y `@HD` | Mantener feed; si no hay guía del feed, usar guía del canal solo si es única |
| Varios streams del mismo canal | Misma ID, URLs distintas | La EPG se comparte por `tvg-id`; los logos también |
| Mismo nombre en países distintos | “24 Horas” Chile/España | Usar país/grupo y `tvg-id`; nunca solo nombre |
| ID obsoleto | `guides.json` con 2.900 IDs fuera de `channels.json` | Comprobar `closed`/`replaced_by`; usar el reemplazo si existe |
| Canal cerrado | `closed` no nulo | No asignar EPG nueva; conservar reproducción si la URL funciona |
| Conflicto de guía | Varios sitios para el mismo feed | Elegir por idioma/país/estabilidad y registrar la elección; no mezclar |

### 5.4 Persistencia de identidad y favoritos

Los favoritos guardados actualmente solo tienen `{kind, name, group, url, subs, src}` **[HECHO]**. Reglas:

- **Favoritos nuevos:** al guardar con `ToggleFavOrDelete()` (`MainScene.brs:255`), añadir campos opcionales `tvgId`, `tvgName`, `logoUrl` y `epgId` cuando existan. No cambiar el esquema obligatorio ni el significado de `url`.
- **Favoritos existentes:** no reescribir ni migrar de forma destructiva. La URL sigue siendo el mecanismo de recuperación; si falta `tvgId`, se enriquece en memoria por URL exacta.
- **Búsqueda al cargar:** primero `m.channels` por URL exacta; después el catálogo por URL exacta (`streamMap`); si no hay coincidencia, se muestra el favorito sin EPG/logo de catálogo.
- **Nombres:** nunca se usan como identificador único. El nombre normalizado solo puede proponer un candidato para revisión, no asignar EPG automáticamente.
- **Canales con varios feeds:** la identidad es `canal@feed`. Varios streams del mismo feed comparten EPG y logo. Varios feeds del mismo canal no comparten programación automáticamente; se usa el feed exacto y, solo si el catálogo lo marca como principal y único, un fallback aprobado.
- **Misma URL en dos canales:** se resuelve por el contexto de la fuente activa y por el `tvg-id` exacto. Si sigue siendo ambiguo, no se asigna EPG hasta que exista una regla manual.
- **URL cambiada:** un favorito antiguo sin `tvgId` que cambie de URL no se puede recuperar automáticamente; se conserva el favorito y se muestra sin EPG. No se inventa la asociación.

### 5.5 Correspondencia para fuentes arbitrarias

La app permite cualquier URL M3U. No es viable precalcular todos los catálogos. Estrategia:

- **Logos:** usar `tvg-logo` embebido; no requiere backend.
- **EPG:** si el `tvg-id` está presente en el catálogo estático de la fuente, usar sus datos; si no, mostrar “Sin EPG”.
- **Fase 3:** limitar la EPG precalculada a las fuentes por defecto y a una lista de IDs conocidos. Documentar la limitación. Los alias manuales pueden ampliar la cobertura, pero requieren revisión.
- **Fuera del alcance inicial:** no se implementa una API dinámica ni una base de datos. Un endpoint `GET /epg?ids=...` o `POST` solo se evaluará después de la Fase 3, si las fuentes arbitrarias lo justifican y si se resuelven privacidad, coste y disponibilidad.

### 5.6 Modelo de correspondencia resultante

```json
{
  "streamUrl": "https://.../playlist.m3u8",
  "tvgId": "DW.de@Espanol",
  "channelId": "DW.de",
  "feed": "Espanol",
  "logoId": "DW.de@Espanol",
  "epgId": "DW.de@Espanol",
  "match": "tvg-id",
  "confidence": 1.0
}
```

- `streamUrl` se conserva exactamente; no se normaliza ni se acorta.
- `channelId` y `feed` permiten resolver logos y metadatos aunque no haya EPG.
- `epgId` es el ID que debe aparecer en `<channel id="...">`.

---

## 6. Arquitectura propuesta

### 6.1 Opciones evaluadas

| Opción | Descripción | Ventajas | Problemas | Decisión |
|---|---|---|---|---|
| A. Descarga directa en Roku | Bajar `channels.json`, `logos.json`, `guides.json` o XMLTV en el dispositivo | Sin backend | 8/5,8/25,6 MB; XMLTV mayor; memoria y parseo inviables; registro 32 KB | **Descartada** |
| B. Archivos locales empaquetados | Incluir catálogo/logos en `pkg:` | Sin red | Aumenta el paquete; datos obsoletos; límite de 4 MB; no escala a fuentes arbitrarias | **Descartada** como solución principal |
| C. Catálogo JSON intermedio + caché | Pipeline externo genera JSON compacto por fuente; Roku lo descarga y cachea | Bajo consumo; control de tamaño; actualizable; desacoplado | Requiere hosting y pipeline | **Recomendada** |
| D. Base de datos local en Roku | SQLite/ficheros indexados | Consultas rápidas | No se identificó una API SQLite nativa en la documentación de BrightScript consultada; complejidad y memoria | **Descartada** |
| E. Servicio de consulta por IDs | API devuelve programación para los IDs solicitados | Flexible para fuentes arbitrarias | Backend, latencia, privacidad, disponibilidad | **Fuera del alcance inicial; reevaluar tras Fase 3** |

### 6.2 Arquitectura recomendada

```
Fuentes M3U                iptv-org API                 iptv-org/epg
    |                           |                            |
    +-----------+---------------+----------------------------+
                |
        Pipeline externo (Node/Python, cron/CI)
        1. Parsear M3U y atributos
        2. Resolver tvg-id -> channel/feed
        3. Elegir logo (tvg-logo / logos.json / alias)
        4. Ejecutar grabbers para IDs mapeados
        5. Convertir XMLTV a JSON compacto (UTC epoch)
        6. Normalizar logos (solo si el spike nativo lo justifica)
        7. Publicar artefactos versionados
                |
        Host estático / CDN / servidor local
        /meta/v12/<sourceHash>/catalog.json
        /meta/v12/<sourceHash>/epg.json
        /meta/v12/<sourceHash>/coverage.json
        /logos/<hash>.png
                |
        Roku (MainScene)
        PlaylistTask  -> canales (sin cambios de reproducción)
        MetadataTask  -> catálogo + EPG (nuevo, en Task)
        MainScene     -> LabelList con iconos + tarjeta EPG
        Video         -> sin cambios
```

El ciclo detallado de actualización de la lista M3U, con revalidación, última versión válida y reconciliación, está en la **sección 15**.

### 6.3 Responsabilidades y desacoplamiento

| Capa | Responsabilidad | No debe hacer |
|---|---|---|
| Reproducción (`PlayChannel`, `StartPlayback`) | URL, formato, subtítulos, reintentos | Conocer logos/EPG o actualizaciones de lista |
| Lista M3U | Descargar, revalidar, validar y confirmar la última versión | Tocar reproducción, favoritos o reconstruir la UI sin reconciliar |
| Catálogo (`m.channels`, favoritos) | Nombre, grupo, URL, campos opcionales | Descargar EPG |
| Logos | Resolver URL, placeholder, caché | Bloquear la lista |
| EPG | Descargar JSON, calcular ahora/siguiente, progreso | Tocar el `Video` |
| UI | Mostrar iconos y tarjeta | Hacer HTTP directamente |

La UI solo consume datos ya resueltos. `MetadataTask` es independiente de `PlaylistTask`; si falla, la app sigue funcionando como hoy.

### 6.4 Hosting inicial: comparación y recomendación

Arquitectura inicial: **un procesador externo, un catálogo JSON, un archivo JSON de programación de 24 h, un directorio de logos normalizados (solo si el spike nativo justifica normalizar) y hosting estático HTTPS**. Sin API dinámica ni base de datos.

| Criterio | GitHub Actions + GitHub Pages | Servidor local existente |
|---|---|---|
| Operación | Workflow programado; poca intervención | Cron/servicio propio; hay que mantenerlo |
| Disponibilidad | Alta; el Roku no depende del PC del usuario | Depende de que el servidor esté encendido y accesible |
| HTTPS | Sí, gestionado por la plataforma | Hay que configurar certificado o usar HTTP en LAN |
| Privacidad | Artefactos públicos; no se envían listas privadas | Datos y logs permanecen en la red local |
| Grabbers EPG | Pueden ser bloqueados por IP de centro de datos | Mayor probabilidad de funcionar desde una IP residencial |
| Límites | Minutos de Actions, tamaño/banda de Pages | Ancho de banda y disponibilidad propios |
| Acceso desde Roku | Funciona fuera de la LAN | Solo LAN salvo VPN/DDNS y puertos |
| Complejidad inicial | Media | Media-baja si el servidor ya existe |
| Legal/redistribución | Los artefactos publicados son públicos | Control de distribución, pero no elimina obligaciones |

**Recomendación inicial única:** GitHub Actions + GitHub Pages para las fuentes públicas por defecto, porque maximiza disponibilidad y minimiza mantenimiento, y no requiere exponer datos del usuario. El servidor local queda como **override opcional** para fuentes privadas o para sitios de EPG que bloqueen GitHub; no se implementa en el MVP.

Esta recomendación **no autoriza** la creación de repositorios, workflows, Pages ni servicios en la Fase 1. La infraestructura de publicación queda pendiente de confirmación explícita del hosting.

**Decisión pendiente:** si la prioridad es privacidad estricta o si los grabadores fallan desde GitHub, cambiar a servidor local como opción inicial. No se construirán ambas opciones a la vez.

El pipeline no debe añadirse a la app empaquetada. El host debe servir HTTPS, soportar gzip y, si sirve imágenes o vídeo, soportar peticiones por rango (`Range`) **[VERIFICADO: recomendación oficial de Roku]**.

### 6.5 Configuración en la app

Añadir una base de metadatos por fuente, opcional:

```brightscript
{ id: "d", name: "robinpalat/streams", url: "...", meta: "https://host/meta/v12/d/" }
```

- Las fuentes antiguas sin `meta` siguen funcionando.
- El usuario puede definir `meta` en el registro o en una pantalla futura.
- Valor por defecto: solo para fuentes conocidas; las fuentes arbitrarias no reciben EPG automática.

No se propone cambiar el esquema obligatorio de `sources` ni la UI de fuentes en la primera fase.

---

## 7. Diseño del modelo de datos

### 7.1 Extensión del canal en memoria

Mantener los campos actuales y añadir opcionales:

```brightscript
{
  kind: "ch",
  name: "DW Espanol (1080p)",
  group: "News",
  url: "https://...",
  subs: "",
  tvgId: "DW.de@Espanol",
  tvgName: "",
  logoUrl: "https://.../DW.png",
  epgId: "DW.de@Espanol"
}
```

Reglas:

- `kind`, `name`, `group`, `url`, `subs` conservan exactamente su significado actual.
- `logoUrl` puede ser la URL original de la M3U o una URL normalizada del catálogo.
- `epgId` puede ser igual a `tvgId` o a un alias resuelto.
- Si no hay datos, los campos valen `""` o `invalid`; el código debe tratarlos como ausentes.

### 7.2 Catálogo compacto (`catalog.json`)

Propuesta:

```json
{
  "schema": 1,
  "version": "2026-11-21T06:00:00Z",
  "generatedAt": 1795240800,
  "sourceId": "d",
  "logoBase": "https://cdn.example/logos/",
  "placeholder": "pkg:/images/logo_placeholder.png",
  "channels": {
    "DW.de@Espanol": {
      "channel": "DW.de",
      "feed": "Espanol",
      "name": "DW Espanol",
      "country": "DE",
      "lang": "es",
      "timezone": "Europe/Berlin",
      "logo": "a1b2c3d4.png",
      "logoW": 120,
      "logoH": 68,
      "epgId": "DW.de@Espanol",
      "hasEpg": true,
      "match": "tvg-id",
      "confidence": 1.0
    }
  },
  "streamMap": {
    "https://.../playlist.m3u8": "DW.de@Espanol"
  }
}
```

Notas:

- `channels` se indexa por `tvg-id`, que es la clave de unión.
- `streamMap` permite enriquecer favoritos antiguos por URL.
- `hasEpg` evita consultar EPG de canales sin datos.
- `logo` es un nombre de archivo con hash de contenido, no una URL de terceros.
- `streamMap` puede ser grande para 2000 canales; el pipeline puede limitarlo a URLs de la fuente o eliminarlo si no se necesita.

### 7.3 EPG compacta (ventana móvil de 24 h)

No se limita el JSON a dos programas. Para Fase 3 se publica una ventana de programación:

- `windowStart = T0 - 6 h`: margen para incluir programas ya empezados.
- `windowEnd = T0 + 24 h`: mínimo de 24 h hacia delante, ampliable si la fuente lo permite.
- Se incluyen todos los programas que solapen `[windowStart, windowEnd]`, incluidos los que empiezan antes y terminan después.

Ejemplo (extracto; el archivo real incluye todos los programas de la ventana):

```json
{
  "schema": 1,
  "version": "2026-11-21T06:00:00Z",
  "generatedAt": 1795240800,
  "windowStart": 1795219200,
  "windowEnd": 1795327200,
  "refreshAfter": 1795262400,
  "validUntil": 1795327200,
  "channels": {
    "DW.de@Espanol": {
      "programCount": 48,
      "unknownDurationCount": 1,
      "lastStop": 1795327200,
      "endKnown": true,
      "programs": [
        { "s": 1795219200, "e": 1795240800, "t": "Programa en curso", "d": "...", "c": "news" },
        { "s": 1795240800, "e": 1795244400, "t": "Programa 2", "d": "...", "c": "news" },
        { "s": 1795244400, "t": "Programa 3 sin stop", "d": "...", "c": "documentary", "ep": "S1E2" },
        { "s": 1795249800, "e": 1795253400, "t": "Programa 4", "d": "...", "c": "movie" }
      ]
    }
  }
}
```

- `s`: inicio en segundos epoch UTC; obligatorio.
- `e`: fin en segundos epoch UTC; **opcional**. Si falta, la duración es desconocida.
- `t`: título.
- `d`: descripción, truncada en el servidor (por ejemplo, 300 caracteres).
- `c`: categoría.
- `ep`: episodio/temporada si existe.
- `i`: imagen opcional del programa.
- `programCount`: número real de programas del canal; incluye los de duración desconocida. En el ejemplo se muestran solo cuatro por brevedad.
- `unknownDurationCount`: programas del canal con `s` válido y sin `e`.
- `lastStop`: mayor fin conocido del canal; si no hay ningún fin conocido, `null`.
- `endKnown`: indica si el final de la programación del canal está cubierto por un `stop` conocido.
- `validUntil`: fin de la ventana publicada; no es lo mismo que `refreshAfter`.
- `refreshAfter`: instante recomendado para volver a consultar el manifiesto; puede ser anterior a `validUntil`.
- El ejemplo es un extracto: `programCount` y `lastStop` corresponden al archivo real, no a las cuatro entradas mostradas.
- El dispositivo calcula ahora/siguiente usando `s` y, cuando existe, `e`; no requiere que el servidor conozca el instante de visualización.

Reglas de comportamiento:

- **Ahora:** programa con `s <= now < e`. Si un programa no tiene `e`, se considera actual desde `s` hasta el `s` del siguiente programa, si existe; si no existe siguiente, permanece actual con duración desconocida. No se inventa un `e`.
- **Progreso:** solo se calcula si existen `s` y `e` válidos. Sin `e`, mostrar “Duración desconocida” y no barra de progreso.
- **Siguiente:** programa con `s >= now` de menor `s` dentro de la ventana; si no existe, no se muestra siguiente.
- **Hueco:** si no hay programa actual pero sí uno futuro, mostrar “Sin programa en este momento” y el siguiente.
- **Programación agotada:** si `endKnown=true` y `now >= lastStop`, no mostrar un programa caducado; mostrar “Sin programación actualizada” y solicitar refresco. Si `endKnown=false`, no afirmar que la programación terminó: mostrar “Duración desconocida” y refrescar.
- **Ventana agotada:** si `now >= windowEnd` o `now < windowStart`, no mostrar datos como actuales; usar la caché anterior solo si sigue siendo válida y, si no, degradar.
- **Fuente incompleta:** si el origen solo ofrece menos de 24 h o no ofrece `stop`, publicar lo disponible, ajustar `windowEnd`/`lastStop`/`endKnown` y marcar la limitación; no inventar programas ni duraciones.

Frecuencias separadas:

| Etapa | Frecuencia | Responsable |
|---|---|---|
| Generación (grabbers) | Diaria o cada 6 h según el sitio; al menos una vez cada 24 h | Pipeline externo |
| Publicación | Tras una ejecución completa y validada; versión inmutable | Pipeline |
| Consulta de manifiesto (`latest.json`) | Al arrancar/cargar playlist y cuando `now >= refreshAfter`; nunca por cada zapping | `MetadataTask` |
| Descarga de `catalog.json`/`epg.json` | Solo si cambió la versión del manifiesto, falta la caché o la caché es inválida | `MetadataTask` |
| Refresco visual | Cada 30–60 s desde memoria; sin red | `Timer` de `MainScene` |

La ventana de 24 h cubre con margen el período de validez nominal de la caché (3–6 h). Si una descarga falla, la app puede seguir usando datos hasta `lastStop`/`windowEnd`; cuando se agotan, degrada y no presenta programas caducados.

Para fuentes con muchos canales, el archivo de 24 h se divide por grupo/país en **shards que conservan la ventana completa**; no se reduce la ventana a dos programas. La Fase 5 puede añadir `epg_grid.json` con 48–72 h, solo para páginas de rejilla.

### 7.4 Presupuesto de tamaño

Estimaciones **[HIPÓTESIS]**, a validar con datos reales. No son mediciones:

| Artefacto | Canales | Tamaño estimado | Decisión |
|---|---:|---:|---|
| `catalog.json` | 51 | 15–40 KB | Aceptable |
| `catalog.json` | 2000 | 600 KB–1,5 MB | Límite; considerar shards |
| `epg.json` (24 h + 6 h de margen) | 51 | 200–500 KB | Aceptable |
| `epg.json` (24 h + 6 h de margen) | 2000 | 10–30 MB | **Inviable en un solo archivo; shards por grupo** |
| `epg_grid.json` (48 h, página de 50 canales) | 50 | 500 KB–1,5 MB | Aceptable para Fase 5 |
| Logo normalizado 16:9 | 1 | 3–8 KB | Aceptable |
| 500 logos en caché nativa | 500 | 1,5–4 MB | A validar; no se fuerza caché propia |
| XMLTV completo | global | Decenas/cientos de MB | **Nunca en dispositivo** |

### 7.5 Caché y claves

- **Logos:** usar primero la caché nativa de imágenes de Roku. **No se implementa LRU propio en la Fase 2.** Solo si las mediciones demuestran que la caché nativa es insuficiente se evaluará una caché `cachefs` simple, con límite explícito y sin LRU inicial.
- Catálogo: `cachefs:/meta_<sourceId>_<version>.json`.
- EPG: `cachefs:/epg_<sourceId>_<version>.json`.
- Registro: solo `meta_base`, `epg_opt_in`, `last_meta_version` y contadores pequeños. Nunca el JSON completo.
- Versiones inmutables: si falla una descarga o el parseo, se conserva la versión anterior en memoria/caché.

### 7.6 Compatibilidad con datos existentes

- `favs` y `sources` no cambian de estructura obligatoria.
- Los campos nuevos son opcionales.
- Las URLs de streaming no se modifican.
- Los nombres y grupos se conservan; no se “limpian” en la lista para no alterar la UI actual.
- Cualquier migración de caché debe ser tolerante a archivos ausentes o corruptos.

---

## 8. Diseño de interfaz

### 8.1 Logos en la lista

La opción de menor riesgo es mantener `LabelList` y asignar iconos por elemento:

```brightscript
node = root.CreateChild("ContentNode")
node.title = p + " " + f + " " + it.name
node.HDListItemIconURL = logoUri
node.HDListItemIconSelectedURL = logoUri
```

- `HDListItemIconURL` y `HDListItemIconSelectedURL` están documentados **[VERIFICADO]**.
- La app usa `ui_resolutions=hd`, por lo que la variante HD es suficiente.
- El escalado exacto del icono dentro de la fila **no está documentado**; hay que probarlo **[PENDIENTE]**.
- **Fase 2a obligatoria (spike):** antes de construir cualquier pipeline de logos, probar la carga nativa de `LabelList` con 50, 500 y 2000 elementos. Medir:
  - peticiones HTTP de imagen y si se limitan a filas visibles;
  - memoria y texturas;
  - tiempo de apertura del panel y fluidez de scroll;
  - comportamiento con HTTPS, red lenta, URL inválida y formatos incompatibles;
  - proporciones con logos horizontales, cuadrados y verticales.
- La documentación oficial de Roku indica que los nodos de lista/grid con componentes de elemento crean componentes para los elementos visibles **[VERIFICADO]**. Para `LabelList` hay que confirmar el comportamiento concreto de sus iconos; no se asume.
- **No implementar LRU ni caché de imágenes propia en la Fase 2.** Si la caché nativa es suficiente, no se añade complejidad. Solo si el spike demuestra lo contrario se evaluará una caché `cachefs` simple.
- Para evitar deformaciones, si la carga nativa no conserva la proporción, el pipeline puede entregar un PNG con lienzo 16:9, fondo transparente, logo centrado y padding uniforme. Esto es un fallback, no el requisito inicial.
- Tamaño recomendado si se normaliza: lienzo 120×68 px o 96×54 px; altura visible del logo 32–40 px en una fila de 44 px.
- Si no hay logo, usar `images/logo_placeholder.png` (nuevo, empaquetado) o no asignar icono. La segunda opción puede desplazar el texto; probar ambas.
- Si `LabelList` intenta cargar todos los elementos a la vez, la mitigación es observar `itemFocused` y asignar iconos a un rango de ±8 elementos **[HIPÓTESIS]**. Si no funciona, evaluar `RowList` de una sola fila con componente de elemento; implicaría más cambios de UI y se pospone.

### 8.2 Tarjeta EPG para el canal enfocado

Añadir un `Group` en el panel, a la derecha de la lista:

```text
+-------------------------------------------------------------+
| [Playlist]  Favoritos (n)  Fuentes (n)          búsqueda…    |
| 51 canales                                                  |
| +---------------------------+  +--------------------------+ |
| | > * DW Espanol            |  | [LOGO]                   | |
| |   Mega (Chile)            |  | DW Espanol               | |
| |   ...                     |  | Ahora 20:00–21:00        | |
| |                           |  | Documental               | |
| |                           |  | Descripción…             | |
| |                           |  | [########----] 60%       | |
| |                           |  | Después 21:00–22:00      | |
| |                           |  | Película                 | |
| +---------------------------+  +--------------------------+ |
| OK elegir  Play favorito  < > pestaña  FF buscar  ...       |
+-------------------------------------------------------------+
```

Cambios propuestos:

- `itemSize` de `LabelList` de `[1200,44]` a `[820,44]` (o `[860,44]`).
- La tarjeta ocupa el espacio restante a la derecha.
- Observar `m.list.itemFocused` (nuevo) para actualizar la tarjeta sin cambiar `itemSelected`.
- El logo de la tarjeta usa `Poster` con:
  - `loadWidth`/`loadHeight` para escalar,
  - `loadDisplayMode="scaleToFit"` para no deformar,
  - `failedBitmapUri="pkg:/images/logo_placeholder.png"`,
  - `loadSync=false` (por defecto) para no bloquear.
- Campos de la tarjeta:
  - nombre del canal y grupo,
  - “Ahora: título” con hora local de inicio y, si existe, fin; si falta `stop`, “Duración desconocida”,
  - descripción (máximo 2–3 líneas; `Label` con `wrap=true`),
  - barra de progreso solo si existen `s` y `e` (Rectangle de fondo + Rectangle de relleno, o `ProgressBar` si se valida),
  - “Después: título” con hora,
  - “Sin información de programación” si no hay EPG.
- Actualización:
  - recalcular ahora/siguiente cada 30–60 s con un `Timer`,
  - no hacer red en cada tecla,
  - no cambiar el foco del `LabelList`.

### 8.3 EPG durante la reproducción

Opcional en Fase 3, recomendado para Fase 4:

- Una barra discreta en la parte inferior con logo, “Ahora: …”, hora y progreso.
- Se muestra al cambiar de canal y se oculta a los 8–10 s.
- No debe tapar subtítulos ni controles; usar la zona inferior con fondo semitransparente.
- Si no hay EPG, no mostrar la barra.

### 8.4 Estados y mensajes

| Estado | UI |
|---|---|
| Logo cargando | Placeholder o hueco reservado; nunca bloquear |
| Logo falla | `failedBitmapUri` o placeholder |
| Sin logo | Placeholder uniforme |
| EPG cargando | “Cargando programación…” solo si el canal tiene `hasEpg` |
| Sin EPG | “Sin información de programación” |
| Programa sin `stop` | “Duración desconocida”; sin barra de progreso; no inventar fin |
| EPG obsoleta | Marca discreta “datos de HH:MM”; no mostrar un programa caducado como actual |
| Programación agotada | “Sin programación actualizada”; solicitar refresco; no inventar |
| Ventana agotada o reloj desajustado | No presentar datos como actuales; degradar o refrescar |
| Error de red | Usar caché; si no hay, ocultar tarjeta; no reintentar en bucle |
| Programa ausente entre dos | Mostrar “Sin programa en este momento” y el siguiente |
| Lista actualizada | Indicador discreto “Lista actualizada”; sin modal ni reinicio |
| Lista en cuarentena | No cambiar la lista; aviso discreto en el estado de fuentes; sin modal |

### 8.5 Rejilla EPG completa (Fase 5)

Distinción clara:

- **Fase 3** es una tarjeta de ahora/siguiente, no una parrilla.
- **Fase 5** sería una vista de rejilla con filas de canales y columnas de tiempo, desplazamiento horizontal/vertical, salto de día y detalle de programa.
- Requiere una ventana de datos mucho mayor y, probablemente, paginación por grupo/país.
- No es razonable cargar 24–48 h de 2000 canales en un Roku de baja gama. La rejilla, si se hace, debe limitarse a un subconjunto visible (por ejemplo, 20–50 canales y 6–12 h por página) y cargar más al desplazar.
- Se recomienda posponerla hasta medir el rendimiento real de la Fase 3.

---

## 9. Estrategia de rendimiento y caché

### 9.1 Principios

1. No procesar XMLTV ni JSON de varios MB en el dispositivo.
2. No bloquear la reproducción ni la navegación por logos o EPG.
3. Descargar solo el subconjunto de la fuente activa.
4. Cachear en `cachefs` con versiones inmutables y tolerancia a evicción.
5. Usar el registro solo para ajustes pequeños.
6. Degradar con gracia: si falla la red, la app se comporta como hoy.
7. La lista M3U tiene su propio ciclo cache-first, validación y última versión válida (sección 15); nunca se actualiza por zapping, foco o navegación.

### 9.2 Presupuestos provisionales y método de medición

Los presupuestos de la versión anterior eran hipótesis. Se mantienen solo como objetivos provisionales y **no se consideran mediciones ni criterios de aceptación hasta ejecutar las pruebas**.

Hechos de partida:

- `index.m3u` de iptv-org: 2,67 MB; la app ya lo descarga para fuentes que lo usen **[VERIFICADO]**.
- Un XMLTV de una sola fuente puede ser de varios MB; se procesa en servidor, no en Roku **[VERIFICADO]**.
- `ParseJSON` convierte un string en un AA que ocupa más memoria que el string; juntos pueden ser problemáticos con JSON grandes **[VERIFICADO: recomendación oficial de Roku]**.
- Roku recomienda evitar descargas grandes, filtrar/optimizar/paginar en servidor, y no pasar AAs grandes por campos SceneGraph **[VERIFICADO]**.
- Roku recomienda reducir el tamaño y número de imágenes, no escalarlas en el dispositivo y componerlas en servidor **[VERIFICADO]**.
- Los nodos de lista/grid con componentes de elemento (por ejemplo, `RowList`, `MarkupList`, `MarkupGrid`) crean componentes para elementos visibles **[VERIFICADO]**; el caso de `LabelList` debe medirse.
- `cachefs` puede expulsar datos si la memoria del sistema baja **[VERIFICADO]**.

Objetivos provisionales **[HIPÓTESIS, medir]**:

| Métrica | Objetivo provisional | Método |
|---|---|---|
| Descarga de catálogo | < 100 KB para 51 canales | Medir bytes reales y tiempo p50/p95 con red normal, lenta y offline |
| Descarga de EPG (24 h) | ≤ 500 KB para 51 canales | Medir bytes reales, gzip y tiempo p50/p95 |
| Parseo de catálogo | < 50 ms para 51 canales | Cronometrar `ParseJson` en Task con fixtures |
| Parseo de EPG (24 h) | < 200 ms para 51 canales | Cronometrar `ParseJson` y construcción del índice ahora/siguiente |
| Hash + parseo de M3U (2,67 MB) | < 1 s en Task (provisional) | Cronometrar normalización, FNV y `ParseM3U`; no ejecutar en render thread |
| Memoria adicional | < 8 MB en gama baja | Roku Resource Monitor antes/después; vigilar swap y cierres |
| Logos | Sin bloqueo; peticiones acotadas a filas visibles | Contar solicitudes y medir tiempo hasta primer logo |
| Navegación | Apertura de panel sin aumento > 200 ms | Medir antes/después con 51 y 2000 canales |
| Refresco en segundo plano | Sin caída de frames ni descargas duplicadas | Instrumentar timestamps y observar Resource Monitor |

Pruebas obligatorias de rendimiento:

1. **Descarga:** medir bytes, gzip, tiempo y errores con red normal, 3G simulada, DNS fallido y timeout.
2. **Parseo JSON:** ejecutar fixtures de 51, 500 y 2000 canales con ventana de 24 h; medir tiempo y memoria. Probar en `Task`, no en el hilo de render.
3. **Memoria:** medir con Roku Resource Monitor en un dispositivo de 512 MB; comprobar swap, memoria de texturas y cierres.
4. **Renderizado de logos:** contar peticiones, medir tiempo hasta el primer logo y scroll con 50/500/2000 elementos.
5. **Navegación:** medir apertura de panel, cambios de pestaña, búsqueda y zapping antes/después.
6. **Actualización en segundo plano:** verificar que no bloquea, no duplica descargas y no interfiere con la reproducción.
7. **Serialización:** evitar `FormatJson` sobre estructuras grandes; no es necesario para cachear si se escribe el string recibido.
8. **M3U:** medir normalización, hash y parseo de 2,67 MB en `Task`; verificar que no bloquea la UI ni duplica memoria de forma excesiva.

Los resultados se registran en `performance.md` o en el informe de fase. Si un objetivo no se cumple, se ajusta el diseño (shards, ventana, carga por grupo) antes de continuar.

### 9.3 Caché

| Dato | Ubicación | TTL / invalidación | Evicción |
|---|---|---|---|
| Lista M3U | `cachefs:/pl_<id>_a.m3u` / `_b.m3u` + metadatos (propuesto; ver 15.6) | TTL 15 min; chequeo 60 min; 6 h sin validadores | Se puede perder; usar memoria o recargar |
| Catálogo | `cachefs:/meta_<source>_<version>.json` | Nueva versión, caché ausente o inválida | Se puede perder; recargar |
| EPG | `cachefs:/epg_<source>_<version>.json` | Nueva versión, caché ausente o inválida; `refreshAfter` solo gobierna la consulta del manifiesto | Se puede perder; recargar |
| Logos | Caché nativa de imágenes de Roku | Según Roku | No controlada por la app |
| Logos (solo si se demuestra necesario) | `cachefs:/logo_<hash>.png` | Inmutable por hash | Límite simple; sin LRU inicial |
| Ajustes | Registro | Persistente | Límite 32 KB |

**Advertencia verificada:** `cachefs` se almacena en RAM si no hay tarjeta SD y el sistema puede expulsar datos en cualquier momento **[VERIFICADO]**. No es almacenamiento persistente garantizado. Siempre comprobar la existencia antes de leer y reconstruir si falta.

**Decisión:** no se implementa LRU ni caché de logos propia en la Fase 2. La caché nativa se evalúa primero; una caché `cachefs` solo se justifica si el spike demuestra que la nativa es insuficiente.

### 9.4 Actualización

Manifiesto pequeño `latest.json` con `version`, `catalog`, `epg`, `generatedAt`, `windowEnd` y `refreshAfter`.

El flujo se separa en cuatro pasos:

1. **Consultar el manifiesto** según su política (inicio, `refreshAfter`, reintento/backoff). `refreshAfter` gobierna la consulta del manifiesto, no la descarga de artefactos.
2. **Comparar la versión** de cada artefacto (`catalog`, `epg`) con la versión local.
3. **Descargar un artefacto** únicamente si:
   - su versión cambió;
   - falta la caché local; o
   - la caché existente es inválida/corrupta.
4. **Refrescar la interfaz** únicamente si los datos aplicados cambiaron realmente. Un manifiesto consultado sin cambios no debe provocar `RenderList`, recarga de logos ni reconstrucción de la tarjeta EPG.

Reglas:

- Si la versión no cambia, **no se vuelve a descargar el mismo artefacto** solo porque venció `refreshAfter`.
- Si el manifiesto no cambia, se actualiza el próximo momento de consulta y se aplica backoff si hubo fallo; no se descargan catálogo/EPG.
- Si la caché del artefacto falta o está corrupta, se descarga aunque la versión del manifiesto sea la misma; es una reparación, no una actualización de versión.
- Si la descarga falla, se conserva la última caché válida y se aplica backoff.
- No actualizar en cada cambio de canal ni en cada tecla.
- **La lista M3U se rige por la sección 15**: no se actualiza por zapping, foco ni navegación; tiene su propio TTL, validadores y última versión válida.
- Los artefactos se reemplazan completos por versión; no se propone una actualización incremental byte a byte. El ahorro proviene de no descargar si la versión no cambia y de limitar el subconjunto al de la fuente activa.

Alternativa de revalidación del manifiesto: `If-None-Match`/ETag. **`GetToString()` descarta cabeceras** **[VERIFICADO]**; para condicionales hay que usar `AsyncGetToString()` y leer `roUrlEvent`, o confiar en el manifiesto de versión. La vía del manifiesto es más simple y robusta.

### 9.5 Red y errores

- Toda descarga nueva en `Task` con `roUrlTransfer` y `SetCertificatesFile("common:/certs/ca-bundle.crt")`, igual que `PlaylistTask` **[HECHO]**.
- Configurar timeout y `SetMinimumTransferRate` para no colgar la tarea **[VERIFICADO: existen]**.
- `EnableEncodings(true)` para aceptar gzip **[VERIFICADO]**.
- Backoff acotado (por ejemplo, 2/4/8 s) y un máximo de intentos por sesión; no reintentar indefinidamente.
- Si el JSON está corrupto o truncado, descartar la versión nueva y conservar la anterior.
- Para la M3U, usar `AsyncGetToString()` y cabeceras condicionales; no usar `GetToString()` si se necesitan ETag/Last-Modified (sección 15.5).
- No escribir en el registro desde el hilo de UI en cada actualización.

### 9.6 Compatibilidad con generaciones de Roku

- `manifest` solo declara `ui_resolutions=hd`; no hay `min_os` **[HECHO]**. Hay que definir la versión mínima objetivo **[PENDIENTE]**.
- Evitar SVG (no está en los formatos soportados por `Poster`: JPEG/PNG/WebP) **[VERIFICADO]**. Convertir a PNG en el servidor.
- Evitar WebP si hay dispositivos anteriores a Roku OS 9.4 **[VERIFICADO: soporte desde 9.4]**. Usar PNG como formato universal.
- Evitar imágenes grandes; escalar en servidor y usar `loadWidth`/`loadHeight`.
- Evitar miles de texturas simultáneas; cargar logos por ventana.
- Probar en un dispositivo de 512 MB de RAM y en uno moderno.

### 9.7 Presupuesto de caché recomendado

Propuesta inicial, ajustable tras medir:

- EPG: máximo 1–2 MB por fuente; si la ventana de 24 h supera el presupuesto, dividir por grupo en shards.
- Catálogo: máximo 1 MB por fuente.
- Logos: prioridad a la caché nativa de Roku; no se fija un presupuesto propio en la Fase 2.
- Solo si se implementa caché propia: máximo 8 MB globales con límite simple, no LRU, y solo después de demostrar que la caché nativa no basta.
- Borrar versiones antiguas de EPG/catálogo antes de ampliar el límite.

---

## 10. Plan de implementación por fases

Cada fase es independiente y verificable. Ninguna fase debe romper la reproducción.

### Fase 0 (previa, opcional): línea base y protecciones

**Objetivo:** congelar el comportamiento actual antes de tocar nada.

- Capturar una lista de canales de referencia de las tres fuentes por defecto (nombre, grupo, URL, orden) y una grabación de los flujos manuales.
- Medir tiempos de arranque/carga y memoria en el dispositivo objetivo.
- Definir la versión mínima de Roku OS.
- No modificar código.

**Entregable:** `baseline/` fuera del paquete o documento de resultados.  
**Dificultad:** baja.  
**Riesgo:** no hacerlo y no poder demostrar regresiones.

### Fase 1: modelo de datos, metadatos y generador local

**Objetivo:** capturar y conservar `tvg-id`/`tvg-logo`/`tvg-name` sin cambiar la reproducción, definir el modelo de correspondencia y preparar un **generador local de catálogo y fixtures**. Esta fase no publica datos ni crea infraestructura.

**Archivos a modificar:**

- `components/PlaylistTask.brs`: añadir `tvgId`, `tvgName`, `logoUrl` a cada canal usando `GetAttr`; conservar `kind`, `name`, `group`, `url`, `subs` exactamente.
- `components/MainScene.brs`: propagar campos opcionales en favoritos, `m.temp` y `m.current`; no tocar `PlayChannel`/`StartPlayback`.
- `source/util.brs`: helpers de normalización e identidad.
- Nuevo `source/catalog.brs` (o similar): estructuras y lookup local.
- Generador local de catálogo y fixtures (herramienta de desarrollo, fuera del paquete Roku): produce un `catalog.json` de prueba y casos de correspondencia; no se despliega.

**Componentes nuevos:** esquema `catalog.json`, generador local, tabla de alias/overrides, fixtures.

**Dependencias:** ninguna nueva en Roku. El generador local puede usar Node.js o Python solo en desarrollo; no se autoriza a publicarlo.

**Dificultad:** media.

**Riesgos:** romper el parser por nombres con comas; alterar el orden o los nombres; que el catálogo no cubra fuentes arbitrarias.

**Pruebas:**

- Fixtures M3U con y sin atributos, comillas simples/dobles, `#EXTVLCOPT`, CRLF, nombres con comas, URLs con query, UTF-8.
- Comparar los 51 canales de `robinpalat/streams` y los 19 de `m3u.cl` contra la línea base.
- Verificar favoritos antiguos y nuevos.
- Verificar que la reproducción no cambia.
- Ejecutar el generador local y validar el `catalog.json` de fixtures contra `channels.json`/`feeds.json`; registrar coincidencias y conflictos.

**Criterios de aceptación:**

- Los campos actuales son idénticos para el 100% de los canales de referencia.
- `tvg-id` y `tvg-logo` están presentes cuando existen en la M3U.
- Los favoritos antiguos siguen funcionando.
- No hay cambios en `content.url`, `streamFormat`, subtítulos ni reintentos.
- El generador local produce un catálogo de fixtures válido y reproducible.
- **No se crea ni publica infraestructura:** nada de repositorios externos, GitHub Actions, GitHub Pages, workflows de publicación ni servicios de producción.

**Fuera de Fase 1:** hosting, pipeline de publicación, descarga automática de EPG y cualquier servicio externo. Quedan sujetos a confirmación explícita del hosting y a una fase posterior. La preparación de un generador local no autoriza a publicarlo.

**Fase 1B (nueva, recomendada antes de EPG):** actualización dinámica de la lista M3U. Se detalla en la sección 15.11; no altera la numeración de las fases existentes. Puede ejecutarse en paralelo con logos, pero debe preceder a la EPG para evitar que una actualización de lista pise metadatos ya resueltos.

### Fase 2: integración de logos

**Objetivo:** mostrar logo por canal sin bloquear la navegación.

**Fase 2a obligatoria (spike nativo):**

- Probar `LabelList` con `HDListItemIconURL`/`HDListItemIconSelectedURL` usando `tvg-logo` directo.
- Medir con 50, 500 y 2000 canales: solicitudes de imagen, memoria, texturas, tiempo de apertura y scroll.
- Validar HTTPS, URL inválida, 404, PNG, JPEG, SVG/WebP no soportados, proporciones y red lenta.
- **Puerta de decisión:** si la carga nativa es aceptable, no se implementa caché de logos. Si no lo es, se evalúa una caché `cachefs` simple; no LRU por defecto.

**Archivos a modificar:**

- `components/MainScene.brs`: en `RenderList()` asignar `HDListItemIconURL`/`HDListItemIconSelectedURL`; resolver por `logoUrl` del canal o catálogo; usar placeholder.
- `components/MainScene.xml`: posible ajuste de `itemSize` si se reserva columna; no cambiar el nodo `LabelList`.
- `images/logo_placeholder.png`: nuevo recurso empaquetado.
- `source/logos.brs` (opcional, solo si hay normalización/fallback que justifique): resolución de URI y placeholder.
- Pipeline de logos normalizados (fallback): solo para formatos incompatibles, URLs problemáticas o proporciones inconsistentes; no es obligatorio para todos.

**Componentes nuevos:** normalizador de logos (servidor, opcional), placeholder.

**Dependencias:** ninguna en Roku; `LabelList` nativo.

**Dificultad:** baja (MVP con `tvg-logo` directo); media (normalización/caché solo si el spike la justifica).

**Riesgos:**

- `LabelList` cargue iconos de los 2000 elementos y sature memoria/red.
- Escalado no documentado que deforme o recorte.
- URLs muertas, HTTP, hotlink protection, SVG/WebP no soportados.
- Logos oscuros sobre fondo oscuro.
- Licencias y marcas.

**Pruebas:**

- Canales con logo, sin logo y con URL rota.
- Lista de 2000 elementos; scroll rápido; favoritos; búsqueda; cambio de pestaña.
- Red desconectada; caché nativa vacía/evictada.
- Dispositivo de baja gama; medir memoria y peticiones.
- Comparar proporciones con logos horizontales, cuadrados y verticales.
- Formatos: PNG, JPEG, SVG, WebP, GIF, AVIF; documentar cuáles fallan.
- HTTPS y URL con redirecciones; comprobar soporte de `Range` del host.

**Criterios de aceptación:**

- ≥95% de los canales con `tvg-logo` o logo de catálogo muestran imagen.
- Los canales sin logo muestran placeholder; no hay huecos ni saltos de layout.
- Ningún logo se deforma (validación visual).
- La navegación y el arranque no se bloquean; el tiempo de apertura del panel no aumenta > 200 ms (medido, no supuesto).
- El número de peticiones de imagen está acotado a la ventana visible; si no, se aplica la mitigación por `itemFocused`.
- Sin crashes ni cierres por memoria con 2000 elementos.
- No se añade caché propia si la nativa cumple los criterios.

### Fase 3: EPG básica con ventana de 24 h

**Objetivo:** mostrar programa actual, siguiente, horarios, descripción y progreso para canales mapeados, usando una ventana móvil de al menos 24 h cuando la fuente lo permita, y medir la cobertura efectiva real.

**Archivos a modificar:**

- `components/MainScene.xml`: tarjeta EPG, `Poster`, etiquetas, barra de progreso, `Timer` de actualización.
- `components/MainScene.brs`: observar `itemFocused`; seleccionar ahora/siguiente; renderizar tarjeta; actualizar progreso; estados sin EPG/programación agotada; opcional barra durante reproducción.
- Nuevos `components/MetadataTask.xml` y `.brs` (o `EpgTask`): descarga de catálogo y `epg.json` de 24 h en `Task`.
- Nuevo `source/epg.brs`: parseo del JSON, índice por canal, cálculo de ahora/siguiente, progreso y detección de agotamiento.
- `source/util.brs`: formateo de horas locales y claves de caché.
- Pipeline: grabbers, XMLTV→JSON de 24 h, medición de cobertura, publicación.

**Componentes nuevos:** `MetadataTask`, `epg.brs`, tarjeta EPG, `coverage.json` de auditoría.

**Dependencias:** pipeline externo con `iptv-org/epg`; ninguna dependencia nueva en Roku.

**Dificultad:** media-alta.

**Riesgos:**

- Cobertura efectiva aún no medida; los 19/40 son potenciales de mapeo, no efectivos.
- `m3u.cl` no tiene mapeo directo; los alias manuales pueden añadir cobertura, pero no está garantizado.
- Mapeo incorrecto de feeds regionales.
- Zonas horarias y DST.
- JSON de 24 h demasiado grande o lento de parsear.
- Sitios de EPG que fallan, geobloquean o cambian.
- La tarjeta reduce el ancho de la lista y afecta títulos largos.
- Licencias de redistribución de la EPG.

**Pruebas:**

- Fixtures con ahora dentro, justo al inicio, justo al final, hueco, solapamiento, sin `stop`, sin programas, programa que cruza medianoche y programa que cruza el fin de ventana.
- Programa actual con `start` y sin `stop`: cuenta como programa, no calcula progreso y no inventa duración; el siguiente se busca por `start`.
- Último programa sin `stop`: `endKnown=false`; no afirmar que la programación terminó.
- Ventana de 24 h: verificar que el JSON contiene todos los programas que solapan `[T0-6h, T0+24h]` y que ahora/siguiente siguen siendo correctos cerca del final.
- Agotamiento: `endKnown=true` y `now >= lastStop`, `now >= windowEnd`, `now < windowStart`; no mostrar programas caducados.
- Refresco: consulta de manifiesto según `refreshAfter`; descarga de `epg.json` solo si cambia la versión o la caché falta/es inválida; no descargar en cada zapping; refresco visual cada 30–60 s.
- Zonas horarias: `Europe/Madrid`, `America/Santiago`, UTC, cambio de hora.
- Reloj del dispositivo adelantado/atrasado.
- Canal sin EPG, EPG obsoleta, JSON corrupto, shard ausente.
- Cambio rápido de canal; zapping; favoritos; búsqueda.
- Reproducción intacta durante la actualización de EPG.
- **Medición de cobertura efectiva:** ejecutar el procedimiento 4.3.1 y registrar canales con programas, sin programas y fallidos.

**Criterios de aceptación:**

- El archivo `epg.json` cubre al menos 24 h hacia delante (o lo máximo que permita la fuente, documentado) y contiene todos los programas que solapan la ventana.
- Para el 100% de los canales con datos de prueba, ahora/siguiente y horas son correctos durante toda la ventana.
- Los programas con `start` válido y sin `stop` cuentan como programación y se registran como duración desconocida; no se calcula progreso ni se inventa `stop`.
- El progreso está dentro de ±60 s del valor esperado cuando existen `start` y `stop`.
- Los horarios se muestran en hora local del dispositivo.
- Los canales sin EPG, con duración desconocida o con programación agotada muestran un estado claro y no bloquean; nunca se muestra un programa caducado como actual.
- El parseo de 51 canales termina en < 200 ms (medido) y no bloquea el hilo de UI.
- El payload de EPG de 24 h para el conjunto por defecto es ≤ 500 KB (medido); si lo supera, se divide en shards por grupo.
- Se publica `coverage.json` con la cobertura efectiva medida, separada de la potencial.
- La reproducción, el zapping y los subtítulos no cambian.
- Si el pipeline falla, la app se comporta como la versión actual.

### Fase 4: optimización de caché y actualización

**Objetivo:** hacer la integración eficiente, tolerante a fallos y actualizable.

**Archivos a modificar:**

- `components/MetadataTask.brs`: timeout, reintentos acotados, gzip, manifiesto de versión, escritura segura.
- `source/util.brs` / nuevo `source/cache.brs`: existencia, versiones y limpieza de catálogo/EPG.
- `components/MainScene.brs`: refresco en segundo plano, uso de caché obsoleta, no bloquear.
- Pipeline: manifiesto `latest.json`, versionado, gzip, validación y `coverage.json`.

**Componentes nuevos:** manifiesto de versión, gestor de caché de catálogo/EPG.

**Dependencias:** ninguna nueva en Roku.

**Dificultad:** media.

**Riesgos:**

- `cachefs` evictado o corrupto.
- Escrituras parciales.
- Caché que crece sin límite.
- Actualizaciones que consumen batería/red o interfieren con la reproducción.
- Diferencias de comportamiento entre versiones de Roku OS.
- Complejidad innecesaria si se añade caché de logos antes de medir la nativa.

**Pruebas:**

- Modo avión; red lenta; DNS fallido; HTTP 500; timeout; JSON truncado.
- Evicción manual de `cachefs`; reinicio; cambio de versión.
- Manifiesto sin cambios con `refreshAfter` vencido: no descargar catálogo/EPG ni reconstruir la UI.
- Caché de artefacto ausente o corrupta con versión de manifiesto sin cambios: descargar solo para reparar.
- Verificar que no se descarga dos veces la misma versión.
- Verificar límites de tamaño de catálogo/EPG y shards.
- Verificar que la caché nativa de imágenes se usa sin intervención de la app.
- Verificar que el registro no supera unos pocos KB.

**Criterios de aceptación:**

- Una sola descarga de cada artefacto por fuente y versión; si la versión no cambia, no se descarga aunque venza `refreshAfter`.
- Excepción controlada: si la caché del artefacto falta o es inválida, se descarga para repararla.
- Arranque offline con caché válida en < 1 s adicional.
- Fallo de red no bloquea ni muestra errores intrusivos.
- Caché de catálogo/EPG dentro del presupuesto definido; versiones antiguas se eliminan.
- No se añade caché de logos propia salvo que el spike demuestre que la nativa es insuficiente.
- Ninguna escritura deja el sistema en un estado irrecuperable.
- El registro permanece pequeño (objetivo: < 8 KB).

**Fase 4B (nueva, opcional después de 1B):** reconciliación visual diferida, refresco periódico de la fuente activa y estadísticas de cambios. Se detalla en la sección 15.11.

### Fase 5: EPG completa (opcional)

**Objetivo:** evaluar y, si se aprueba, implementar una rejilla EPG.

**Archivos a modificar:**

- Nuevo `components/GuideGrid.xml/.brs`.
- Nuevo `components/GuideItem.xml/.brs` (celda de programa).
- `components/MainScene.brs`: abrir/cerrar la guía, conservar reproducción.
- Pipeline: `epg_grid.json` con 48–72 h, paginado por grupo/país/ventana; los shards conservan la ventana completa.

**Componentes nuevos:** rejilla, navegación temporal, detalle de programa.

**Dependencias:** ninguna nueva en Roku; más datos y más pruebas.

**Dificultad:** alta.

**Riesgos:**

- Memoria y texturas.
- Scroll horizontal/vertical y foco complejo.
- Datos de 24–48 h demasiado grandes.
- Canales sin EPG que rompen la alineación temporal.
- Regresión en la navegación existente.

**Pruebas:**

- 20–50 canales, 6–12 h, varias resoluciones.
- Scroll rápido, saltos de día, programas que cruzan medianoche.
- Canales sin EPG.
- Volver al reproductor sin perder el estado.
- Dispositivo de baja gama.

**Criterios de aceptación:**

- La rejilla abre en < 2 s para el subconjunto definido.
- Memoria acotada y sin cierres.
- Navegación clara y reversible.
- No se altera la reproducción ni la navegación existente.
- Si no se cumplen los presupuestos, se cancela la fase y se mantiene la tarjeta ahora/siguiente.

### Resumen de fases

| Fase | Valor | Dificultad | Riesgo | Dependencia externa |
|---|---|---|---|---|
| 0 | Línea base | Baja | Bajo | Ninguna |
| 1 | Modelo, mapping y generador local | Media | Medio | API iptv-org (local, sin publicación) |
| 1B | Actualización dinámica de M3U | Media-alta | Medio | Servidores M3U |
| 2 | Logos (spike nativo + integración) | Baja (spike) / media (pipeline) | Bajo-medio | M3U; host solo si se normaliza |
| 3 | EPG 24 h (ahora/siguiente) | Media-alta | Alto | Grabbers + host |
| 4 | Caché y actualización de catálogo/EPG | Media | Medio | Host versionado |
| 4B | Reconciliación visual y refresco periódico M3U | Media | Medio | Servidores M3U |
| 5 | Rejilla EPG | Alta | Alto | Dataset paginado |

---

## 11. Riesgos y mitigaciones

| Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|
| Regresión en reproducción | Media | Alto | No tocar `PlayChannel`/`StartPlayback`; pruebas de regresión; feature flags |
| Regresión en navegación | Media | Alto | Mantener `LabelList` y `onKeyEvent`; cambios aditivos; pruebas manuales |
| `LabelList` carga demasiados iconos | Media | Alto | Spike nativo; medir; cargar por ventana; fallback a `RowList` solo si es necesario |
| Caché nativa de imágenes insuficiente | Media | Medio | Medir primero; no construir LRU; evaluar `cachefs` simple solo con evidencia |
| Deformación/recorte de logos | Alta | Medio | Validar proporciones; normalizar a lienzo 16:9 solo si es necesario; `scaleToFit` en `Poster` |
| Logos muertos o bloqueados | Alta | Medio | Normalización/proxy como fallback; placeholder; no hotlink masivo |
| SVG/WebP no soportados | Media | Medio | Validar formatos; convertir a PNG cuando sea necesario |
| Logos con licencia/trademark | Alta | Alto | Revisión legal; atribución; usar `tvg-logo`/fuentes oficiales; no vender |
| Cobertura efectiva de EPG no medida | Alta | Alto | Ejecutar 4.3.1; publicar `coverage.json`; no presentar 21/40 como efectivo |
| EPG con cobertura baja | Alta | Medio | Estado “Sin EPG”; no prometer cobertura total; priorizar canales clave; alias manuales |
| Mapeo incorrecto de feed regional | Media | Alto | Priorizar feed exacto; no usar principal si es ambiguo; revisión manual |
| EPG obsoleta o incorrecta | Media | Medio | `refreshAfter`/`lastStop`; refresco; mostrar hora de datos; no mostrar caducados |
| Programación agotada antes de lo previsto | Media | Medio | `lastStop` por canal; estado claro; refrescar; no inventar |
| Sitios de EPG fallan/geobloquean | Alta | Medio | Múltiples sitios por canal; reintentos en pipeline; monitorización |
| GitHub Actions bloqueado por sitios | Media | Medio | Fallback a servidor local; elegir sitios estables; monitorizar fallos |
| XMLTV demasiado grande | Alta | Alto | Procesar en servidor; subconjuntos; ventana de 24 h, nunca XMLTV en Roku |
| JSON de 24 h demasiado grande | Media | Alto | Shards por grupo que conservan 24 h; medir memoria; gzip |
| Lista M3U truncada o HTML de error | Alta | Alto | Validación estructural; conservar última versión válida; cuarentena |
| Sustitución masiva con igual cantidad | Media | Alto | Indicadores de composición (URLs, `tvg-id`, grupos, duplicados) y cuarentena/confirmación |
| Validación restringe protocolos admitidos | Media | Alto | No filtrar por esquema; inventariar y probar regresión por protocolo |
| Caída brusca legítima de canales | Media | Medio | Umbral sobre mediana; confirmación por segunda lectura; no borrar la anterior |
| Actualización de M3U rompe foco/navegación | Media | Alto | Reconciliación por identidad; aplicar en momento seguro; pruebas de escenarios |
| Actualización cambia la URL de la sesión activa | Baja | Alto | Invariante: no tocar `m.current`, `m.playingUrl` ni `Video`; nueva URL solo para siguiente reproducción |
| Favorito apunta a URL desaparecida | Alta | Medio | No borrar; conservar URL; actualización solo con alta confianza o confirmación |
| Validadores HTTP no soportados | Alta | Medio | Fallback a hash normalizado; TTL más largo; medir ancho de banda |
| Hash/parseo de M3U grande bloquea | Media | Medio | Ejecutar en Task; medir; hash no criptográfico; límites de tamaño |
| `cachefs` evictado total o parcial | Alta | Medio | Sidecars A/B solo si quedan archivos; comprobar existencia; reconstruir; sin garantía ante pérdida total |
| Registro lleno | Baja | Alto | No guardar JSON grande; límite 32 KB; medir |
| Escritura parcial/corrupta | Media | Medio | Versiones inmutables; validar antes de usar; conservar anterior |
| Timeouts/red lenta | Alta | Medio | Timeout, backoff, caché obsoleta, no bloquear UI |
| Zonas horarias/DST | Media | Alto | Epoch UTC en datos; `roDateTime.ToLocalTime()`; pruebas de cambio de hora |
| Reloj del dispositivo incorrecto | Media | Medio | No critical; mostrar según reloj local; opcional `serverNow` |
| Fuentes arbitrarias sin metadata | Alta | Medio | Logos desde M3U; EPG solo si hay ID conocido; mensaje claro |
| Privacidad de listas de usuario | Media | Medio | Evitar enviar listas a un backend; usar artefactos estáticos por fuente |
| Coste/operación del pipeline | Media | Medio | GitHub Actions/cron; cachear; limitar sitios; monitorizar |
| Licencia de EPG/contenido | Alta | Alto | Revisar términos de cada sitio; no redistribuir sin permiso |
| Deriva de IDs de iptv-org | Media | Medio | Refrescar catálogo; usar `replaced_by`; alertas de IDs huérfanos |
| Aumento del paquete Roku | Baja | Medio | No empaquetar logos/EPG; solo placeholder |

---

## 12. Pruebas y criterios de aceptación

### 12.1 Estrategia

No hay infraestructura de pruebas **[HECHO]**. Se propone:

1. **Fixtures de parser y mapping** en texto/JSON, ejecutables con un harness de desarrollo.
2. **Pruebas de dispositivo** en al menos dos generaciones de Roku (baja gama y moderna).
3. **Pruebas de red**: normal, lenta, offline, DNS fallido, HTTP 500, timeout.
4. **Pruebas de caché**: vacía, válida, obsoleta, corrupta, evictada.
5. **Pruebas de rendimiento**: descarga, `ParseJson`, memoria, logos, navegación y refresco en segundo plano.
6. **Medición de cobertura efectiva de EPG** según el procedimiento 4.3.1.
7. **Pruebas de actualización dinámica de M3U**: matriz de 32 escenarios de la sección 15.10, con invariante protegido por caso.
8. **Pruebas de regresión** de reproducción, zapping, favoritos, búsqueda, subtítulos y reintentos.

Si se desea automatizar, evaluar un intérprete BrightScript de desarrollo (`brs`) o un harness de escena de test. Debe ser **solo de desarrollo**, no una dependencia del paquete Roku. Justificación: no existe otra forma de ejecutar lógica BrightScript en CI sin dispositivo.

### 12.2 Matriz mínima de dispositivos

| Dispositivo | Memoria | Roku OS | Objetivo |
|---|---|---|---|
| Stick de baja gama | ~512 MB | Versión mínima a definir | Estrés de memoria y logos |
| Stick/Express moderno | — | Actual | Funcionalidad completa |
| TV/box de gama alta | — | Actual | Rendimiento y UI |

La versión mínima de Roku OS es una decisión pendiente **[PENDIENTE]**. Afecta a WebP, HTTP/2 y APIs disponibles.

### 12.3 Pruebas de regresión obligatorias

- Cargar las tres fuentes por defecto.
- Navegar por carpetas y subir/bajar.
- Buscar con teclado.
- Reproducir un canal; pausar; reanudar; zapping izquierda/derecha.
- Añadir/quitar favoritos; reproducir desde favoritos.
- Cambiar de fuente; añadir una fuente manual.
- Subtítulos: activar, cambiar, desactivar.
- Reintentos: simular error de stream y comprobar la secuencia 2/4/8/16/30 s.
- Entrada ECP (`contentId`) desde `roInput`.
- Cerrar y reabrir la app; comprobar `last_<id>`.
- Inventario de protocolos: probar una URL de cada esquema admitido por la implementación actual (HTTP/HTTPS y cualquier otro verificado) y documentar el resultado; no cambiar `content.url` ni `StartPlayback`.

**Criterio:** todos los flujos anteriores se comportan igual que la línea base, con o sin metadatos/EPG.

### 12.4 Criterios globales de aceptación

- **Cero cambios de contrato** en `PlayChannel`, `StartPlayback`, `Zap`, subtítulos y reintentos.
- **Cero cambios de URL** de streaming.
- **Cero dependencias nuevas** en el paquete Roku.
- **Cero empaquetado** de catálogos/EPG/logos masivos.
- **Actualización M3U no disruptiva:** una respuesta inválida nunca reemplaza la última versión válida; una actualización válida no interrumpe reproducción, no borra favoritos y conserva foco/navegación.
- **Sin descargas redundantes de catálogo/EPG:** manifiesto sin cambios y `refreshAfter` vencido no descarga artefactos; solo se repara una caché ausente/corrupta.
- **Degradación garantizada:** sin red o sin pipeline, la app funciona como la versión actual.
- **Presupuesto de rendimiento:** arranque y apertura de panel sin regresión perceptible; memoria adicional dentro del presupuesto medido y acordado.
- **Presupuesto de datos:** EPG de 24 h ≤ 500 KB para el conjunto por defecto (medido); si se supera, shards por grupo. Los presupuestos de 9.2 son objetivos provisionales hasta medirlos.
- **Trazabilidad:** cada fase entrega resultados medidos, no solo “funciona”; incluye `coverage.json` y mediciones de rendimiento.

### 12.5 Pruebas específicas de EPG

| Caso | Resultado esperado |
|---|---|
| `now` entre `s` y `e` | Programa actual y progreso correctos |
| `now == s` | Programa actual, progreso 0% |
| `now == e` | Pasa al siguiente; no mostrar el anterior |
| Hueco entre programas | “Sin programa en este momento” + siguiente |
| Solapamiento | Elegir el de `s` más reciente; documentar |
| Sin `stop` | Cuenta como programa encontrado; duración desconocida; no progreso; siguiente por `start`; no inventar `stop` |
| Sin EPG | Estado claro, sin errores |
| Cambio de hora | Horas locales correctas antes/después de DST |
| Zona horaria distinta | Mostrar hora local del dispositivo; opcional mostrar zona del canal |
| Reloj adelantado | No romper; el progreso se recorta a 0–100% |
| JSON corrupto | Usar versión anterior o estado sin EPG |
| EPG caducada | Mostrar última copia con aviso; refrescar en segundo plano |
| Ventana de 24 h cerca del final | Ahora/siguiente correctos; al agotarse, no mostrar programas caducados |
| `endKnown=true` y `now >= lastStop` | “Sin programación actualizada”; solicitar refresco |
| `endKnown=false` | “Duración desconocida”; no afirmar que terminó; refrescar |
| `now >= windowEnd` | No usar datos como actuales; refrescar o degradar |
| `now < windowStart` | Tratar como reloj desajustado; no mostrar datos futuros como actuales |
| Programa actual sin `stop` y siguiente conocido | Actual hasta el `start` siguiente; sin progreso; no inventar fin |
| Último programa sin `stop` | `endKnown=false`; “Duración desconocida”; refrescar; no afirmar que terminó |
| Programa que cruza medianoche | Horas locales correctas y progreso correcto |
| Programa que cruza el fin de ventana | Incluido; no se corta artificialmente |
| Fuente con menos de 24 h | Mostrar lo disponible y marcar la limitación |
| Shard ausente | Estado sin EPG para ese grupo; no romper la app |

### 12.6 Pruebas específicas de logos

| Caso | Resultado esperado |
|---|---|
| `tvg-logo` válido | Logo visible; sin bloqueo; carga nativa |
| URL 404 | Placeholder; sin error visible |
| SVG | Se documenta si falla; se convierte a PNG solo si es necesario |
| WebP/GIF/AVIF | Se documenta soporte real; convertir a PNG si falla |
| HTTPS y redirecciones | Carga correcta o placeholder; sin bloqueo |
| Logo muy horizontal/vertical | Sin deformación; validar escalado nativo |
| Sin logo | Placeholder uniforme |
| 2000 canales | Sin crash; solo ventana visible cargada; medir peticiones |
| Scroll rápido | Sin parpadeos graves ni bloqueos |
| Caché nativa vacía/evictada | Recarga; placeholder mientras tanto; sin caché propia |
| Fondo oscuro | Contraste aceptable; validar logos oscuros |

### 12.7 Entregables de medición

- `coverage.json`: cobertura potencial y efectiva por fuente, sitio y canal; motivos de fallo; `programas_sin_stop` y `canales_con_duracion_desconocida` separados.
- `performance.md`: bytes descargados, tiempos p50/p95, milisegundos de `ParseJson`, memoria antes/después, peticiones de imagen y tiempos de navegación.
- `device-matrix.md`: resultados por modelo y versión de Roku OS.
- `label-list-spike.md`: decisión sobre carga nativa de iconos y necesidad o no de caché propia.

Ninguna fase se considera cerrada solo con una impresión visual: debe adjuntar estas mediciones.

---

## 13. Recomendación técnica final

### 13.1 Recomendación

1. **Aprobar Fase 1 y el spike de la Fase 2a.** Los logos son la mejora con mejor relación valor/riesgo: ya vienen en la M3U, `LabelList` soporta iconos y no hace falta tocar la reproducción. Continuar la Fase 2 completa solo si el spike nativo con `tvg-logo` directo pasa las puertas de memoria, navegación y peticiones. Normalizar en servidor solo si es necesario. No implementar LRU ni caché propia sin evidencia.
2. **Aprobar Fase 1B (actualización dinámica de M3U) antes de la EPG.** Es la base para que catálogo, logos y EPG no queden desincronizados cuando la fuente cambia. Implementar cache-first, validación, anomalías, última versión válida y reconciliación segura; no tocar reproducción.
3. **Aprobar Fase 3 solo con un pipeline externo autorizado, ventana de 24 h y cobertura medida.** No descargar XMLTV ni la API completa en el Roku. Generar `catalog.json` y `epg.json` de 24 h por fuente, con `tvg-id` como clave. Medir la cobertura efectiva con 4.3.1; los 19/40 son potenciales, no efectivos. La UI debe mostrar “Sin EPG” cuando corresponda. El hosting debe confirmarse antes de crear el pipeline.
4. **No implementar la rejilla EPG todavía.** Primero medir la Fase 3. Si se hace, que sea paginada por grupo/ventana, no una parrilla global de 2000 canales.
5. **Arquitectura inicial recomendada, no autorizada aún:** procesador externo + catálogo JSON + `epg.json` de 24 h + directorio de logos (solo si hace falta) + hosting estático HTTPS. Sin API dinámica ni base de datos. Recomendación inicial: GitHub Actions + GitHub Pages; servidor local como override opcional. No forma parte de la Fase 1; requiere confirmación de hosting.
6. **Mantener el paquete Roku pequeño.** El pipeline y los datos viven fuera de la app. Solo se empaqueta un placeholder.
7. **No cambiar la reproducción, URLs, subtítulos, zapping, favoritos existentes ni navegación.** Cualquier cambio debe ser aditivo y reversible.

### 13.2 Decisiones que requieren validación del usuario

Antes de iniciar la implementación:

1. **Hosting del pipeline:** se recomienda GitHub Actions + GitHub Pages como opción inicial; confirmar o cambiar a servidor local. ¿Quién lo opera?
2. **Alcance de fuentes:** ¿solo las tres fuentes por defecto o también fuentes arbitrarias añadidas por el usuario?
3. **Cobertura aceptable:** la cobertura efectiva aún no se ha medido. Los 19–21 de 40 son potenciales de mapeo; `m3u.cl` no tiene mapeo directo, pero puede tener alias manuales. ¿Qué cobertura efectiva mínima se exige para aprobar la Fase 3?
4. **Dispositivos objetivo:** versión mínima de Roku OS y modelos de baja gama.
5. **Diseño de UI:** ¿se aprueba reducir el ancho de la lista para una tarjeta EPG, o se prefiere una solución inline/diálogo?
6. **Legal:** revisión de licencias de logos (especialmente tv-logos) y de redistribución de la EPG de cada sitio.
7. **Datos de EPG:** ¿se acepta ejecutar grabadores de iptv-org/epg y publicar su salida? ¿Hay fuentes alternativas con licencia clara?
8. **Privacidad:** ¿se enviará la lista de canales del usuario a algún servicio? La propuesta recomendada evita hacerlo.
9. **Caché:** ¿se acepta que `cachefs` es evictable y que la app debe reconstruir datos? ¿Se acepta depender de la caché nativa de imágenes hasta medirla?
10. **Formatos:** no se confirma PNG como único formato. Primero se prueba la carga nativa de PNG/JPEG/WebP y se convierte a PNG solo lo que falle.
11. **Ventana EPG:** confirmar 24 h hacia delante + 6 h de margen; si el payload excede el presupuesto, confirmar shards por grupo en lugar de reducir la ventana.
12. **TTL de M3U:** confirmar 15 min de frescura, chequeo cada 60 min y 6 h para fuentes sin validadores (sección 15.4).
13. **Anomalías de M3U:** confirmar el umbral inicial de caída (60% de la mediana de las últimas 3 versiones) y la confirmación por segunda lectura idéntica.
14. **Favoritos con URL cambiada:** decidir si se actualiza automáticamente solo con correspondencia única de `tvg-id` + nombre/grupo, o si se exige confirmación del usuario.
15. **Reordenamientos:** decidir si se aplican de inmediato cuando el orden relativo cambia o se difieren hasta cerrar/abrir el panel.
16. **Metadatos de M3U:** confirmar si se guardan solo en `cachefs` (reconstruibles) o también un resumen mínimo en registro. Nunca el contenido completo.
17. **Anomalías de composición:** confirmar los umbrales iniciales de retención de URLs, `tvg-id`, grupos y duplicados; no son definitivos.
18. **Fuente que cambia en cada lectura:** definir aprobación manual o política de estabilización cuando no hay segunda lectura idéntica.
19. **Protocolos:** inventariar qué esquemas reproduce realmente la app antes de validar o restringir; no asumir HTTP/HTTPS como único.
20. **Metadatos por slot:** confirmar sidecars con `sourceId`, versión, hash, estado y `confirmedAt` para recuperación determinista.
21. **Manifiesto de catálogo/EPG:** confirmar que `refreshAfter` solo gobierna la consulta y que un artefacto solo se descarga si cambia la versión, falta la caché o es inválida.

### 13.3 Resultado esperado si se aprueba

- Una app que sigue reproduciendo exactamente igual.
- Listas M3U que se actualizan sin interrumpir la reproducción, sin perder favoritos ni foco, y sin aceptar respuestas inválidas.
- Logos visibles para la mayoría de canales, con reserva para el resto.
- Tarjeta de programación actual/siguiente con horarios, descripción y progreso donde existan datos.
- Una arquitectura de datos desacoplada, cacheada y actualizable sin recompilar la app.
- Una base medible para decidir, más adelante, si merece la pena una rejilla EPG.

---

## 14. Resultado de la segunda auditoría técnica

### 14.1 Problemas detectados

| # | Problema | Evidencia | Severidad |
|---|---|---|---|
| 1 | La cobertura de EPG se presentaba como si fuera efectiva | 21/40 y 19/40 son filas potenciales en `guides.json`; no se ejecutaron grabadores **[VERIFICADO]** | Alta |
| 2 | Se afirmaba que `m3u.cl` no tiene EPG por no tener `tvg-id` | La ausencia de `tvg-id` impide el mapeo directo, no demuestra ausencia de EPG; los alias manuales son posibles **[HECHO + HIPÓTESIS]** | Alta |
| 3 | No había procedimiento para medir cobertura real | Solo se contaban filas de `guides.json`; no se distinguía con programas, sin programas y fallidos **[HECHO]** | Alta |
| 4 | La EPG se limitaba a dos programas | El ejemplo `epg_now.json` solo mostraba ahora/siguiente y no garantizaba 24 h **[HECHO]** | Alta |
| 5 | Timestamps incoherentes en los ejemplos | `generatedAt: 1763704800` no corresponde a la fecha `2026-11-21T06:00:00Z` **[HECHO]** | Media |
| 6 | Frecuencias de generación, publicación, descarga y refresco mezcladas | No había una separación explícita ni comportamiento al agotarse la ventana **[HECHO]** | Media |
| 7 | Estrategia de logos sobredimensionada | Se proponía normalización/caché/LRU antes de probar la carga nativa de `LabelList` **[HECHO]** | Media |
| 8 | Comportamiento nativo de `LabelList` no verificado | El escalado, la carga diferida y el número de peticiones con 2000 canales no están documentados **[PENDIENTE]** | Alta |
| 9 | Identidad de favoritos incompleta | Los favoritos actuales no guardan `tvg-id`; solo URL/nombre/grupo **[HECHO]** | Media |
| 10 | Tratamiento de varios feeds/streams insuficiente | Faltaba una regla explícita para feeds regionales y URLs ambiguas **[HECHO]** | Media |
| 11 | Infraestructura inicial ambigua | Se mencionaban API dinámica, base de datos y dos hosts sin una decisión inicial única **[HECHO]** | Media |
| 12 | Presupuestos de rendimiento sin medición | Eran objetivos plausibles, no resultados **[HECHO]** | Media |
| 13 | Falta de referencias a recomendaciones oficiales de Roku | No se citaban `ParseJSON`, memoria, imágenes ni `cachefs` **[VERIFICADO: documentación oficial]** | Media |
| 14 | Límites de seguridad dispersos | Había que reforzar la naturaleza aditiva, reversible y tolerante a fallos **[HECHO]** | Alta |

### 14.2 Correcciones realizadas al plan

| Corrección | Sección afectada |
|---|---|
| Separar cobertura potencial de cobertura efectiva | 1, 4.3, 4.3.1, 11, 12, 13, Anexo C |
| Añadir procedimiento de medición con grabadores y `coverage.json` | 4.3.1, 10 (Fase 3), 12.7 |
| Rediseñar la EPG como ventana móvil de 24 h + 6 h de margen | 1, 6.2, 7.3, 7.4, 9.2, 9.7, 10 (Fase 3), 12.5 |
| Incluir todos los programas que solapan la ventana, con `programCount` y `lastStop` | 7.3, 7.4 |
| Separar generación, publicación, descarga y refresco visual | 7.3, 9.4 |
| Definir comportamiento al agotarse la programación o la ventana | 7.3, 8.4, 12.5 |
| Corregir timestamps de los ejemplos a epoch de 2026 | 7.2, 7.3 |
| Priorizar `tvg-logo` → `logos.json` → alias tv-logos → placeholder | 4.4, 5.3, 8.1, 13 |
| Añadir spike obligatorio de carga nativa de `LabelList` | 8.1, 10 (Fase 2), 12.6 |
| Eliminar LRU/caché propia como requisito inicial | 7.5, 9.3, 9.7, 10 (Fase 2/4), 13 |
| Añadir `tvg-id` opcional a favoritos nuevos y conservar URL para antiguos | 5.4, 7.1, 7.6 |
| Definir feeds, streams y URLs ambiguas | 5.3, 5.4, 5.6 |
| Fijar arquitectura inicial estática, sin API ni base de datos | 6.1, 6.4, 13, 14.4 |
| Recomendar una única opción inicial de hosting | 6.4, 13.2, 14.4 |
| Convertir presupuestos en hipótesis con método de medición | 9.2, 12.4, 12.7 |
| Incorporar recomendaciones oficiales de Roku | 9.2, 9.3, 9.6, 12.7, Anexo B |
| Reforzar límites de no regresión | 3.1, 12.3, 13.1, 14.5 |

### 14.3 Decisiones todavía pendientes

| Decisión | Estado | Recomendación |
|---|---|---|
| Cobertura efectiva real de EPG | **No medida** | Ejecutar 4.3.1 antes de aprobar la Fase 3 |
| Hosting inicial | **Pendiente** | GitHub Actions + GitHub Pages; servidor local como override opcional |
| Comportamiento nativo de `LabelList` con iconos | **No verificado** | Spike 2a con 50/500/2000 canales |
| Licencias de logos y EPG | **Pendiente** | Revisión legal antes de publicar artefactos |
| Versión mínima de Roku OS | **Pendiente** | Definir según parque de dispositivos |
| Diseño de UI de la tarjeta EPG | **Pendiente** | Aprobar reducción de ancho de lista o alternativa inline/diálogo |
| Umbral de shards para 24 h | **Pendiente** | Medir payload; dividir por grupo si supera 500 KB en el conjunto por defecto |
| EPG para fuentes arbitrarias | **Fuera del MVP** | Reevaluar tras Fase 3; no construir API/DB ahora |
| Caché propia de logos | **No justificada aún** | Solo si el spike demuestra que la nativa es insuficiente |
| Formato de logos | **Pendiente** | Probar PNG/JPEG/WebP nativos; convertir a PNG solo lo que falle |
| Precisión de alias manuales | **Pendiente** | Revisión manual y registro de `matchMethod`/`confidence` |
| Recuperación de caché A/B | **Limitada** | A/B solo con archivos disponibles; sidecars para metadatos corruptos; sin garantía ante pérdida total |
| Descargas de catálogo/EPG | **Pendiente** | `refreshAfter` solo consulta el manifiesto; no descargar artefactos si la versión no cambió |
| Umbrales de composición de M3U | **Pendiente** | Retención de URLs/`tvg-id`/grupos/duplicados; calibrar y no tratar como definitivos |
| Protocolos de reproducción | **Pendiente** | Inventariar esquemas admitidos y probar regresión; no filtrar por HTTP/HTTPS sin verificar |
| Política de fuente que cambia siempre | **Pendiente** | Mantener versión anterior; aprobación manual o estabilización |

### 14.4 Arquitectura inicial recomendada (pendiente de autorización)

**Hechos de diseño:** la app no tiene tests, no tiene pipeline y no debe procesar XMLTV. El paquete ya pesa ~1,9 MB en imágenes y el registro está limitado a 32 KB **[HECHO/VERIFICADO]**.

**Arquitectura recomendada (no autorizada para crear infraestructura en Fase 1):**

```text
GitHub Actions (cron diario/6 h)
  -> lee M3U de fuentes públicas + API iptv-org
  -> mapea tvg-id / channel@feed / alias manual
  -> ejecuta grabbers de iptv-org/epg para IDs mapeados
  -> XMLTV -> epg.json (24 h + 6 h de margen)
  -> genera catalog.json, latest.json, coverage.json
  -> normaliza logos solo si el spike lo justifica
  -> publica en GitHub Pages (HTTPS, gzip, Range)
                |
Roku
  PlaylistTask  -> M3U + tvg-id/tvg-logo (sin tocar playback)
  MetadataTask  -> latest.json + catalog.json + epg.json
  MainScene     -> LabelList con iconos nativos + tarjeta ahora/siguiente
  cachefs       -> catálogo/EPG versionados; sin LRU de logos
  Registro      -> solo ajustes pequeños
```

**Componentes y límites:**

- Procesador externo: Node.js o Python; sin API ni base de datos.
- Artefactos estáticos: `latest.json`, `catalog.json`, `epg.json`, `coverage.json`, y `logos/` opcional.
- Roku: `MetadataTask` independiente de `PlaylistTask`; `MainScene` solo consume datos; `Video` intacto.
- Identidad: `tvg-id` (`canal@feed`) como clave; URL solo para recuperar favoritos antiguos.
- EPG: 24 h móviles; shards por grupo si el tamaño lo exige; nunca XMLTV en el dispositivo.
- Logos: `tvg-logo` nativo; `logos.json` como fallback; tv-logos solo con alias manual; placeholder.
- Sin API dinámica, sin base de datos, sin dependencias nuevas en el paquete Roku.

**Por qué esta opción:** es la de menor complejidad que sigue cumpliendo los requisitos, evita procesar datos grandes en Roku y permite medir cobertura/rendimiento antes de ampliar. GitHub Pages maximiza disponibilidad; el servidor local queda como override si la privacidad o los bloqueos de EPG lo exigen.

### 14.5 Alcance mínimo viable

**Incluido en el MVP:**

1. Capturar `tvg-id`, `tvg-logo` y `tvg-name` en `PlaylistTask`, sin alterar campos existentes.
2. Spike 2a de carga nativa de iconos en `LabelList`.
3. Logos con prioridad `tvg-logo` → `logos.json` → alias tv-logos → placeholder.
4. `catalog.json` para las fuentes por defecto.
5. `epg.json` de 24 h + 6 h de margen para canales mapeados.
6. Tarjeta de ahora/siguiente con horarios, descripción y progreso.
7. Caché versionada de catálogo/EPG en `cachefs`, tolerante a evicción.
8. Medición de cobertura efectiva y de rendimiento.
9. Favoritos nuevos con `tvg-id` opcional; favoritos antiguos por URL.

La Fase 1 del MVP usa un generador local; **no incluye hosting, publicación ni servicios externos**. Cualquier despliegue de catálogo/EPG requiere autorización separada del hosting.

**Excluido del MVP:**

- Rejilla EPG completa.
- API dinámica o base de datos.
- EPG para fuentes arbitrarias sin catálogo.
- Caché LRU o caché propia de logos.
- Procesamiento de XMLTV en Roku.
- Cambios en reproducción, URLs, subtítulos, zapping, favoritos existentes o navegación.

**Puertas de aprobación:**

- **Puerta A (logos):** el spike nativo no degrada navegación/memoria y los logos se muestran sin bloqueo.
- **Puerta B (EPG):** la cobertura efectiva medida es aceptable para el usuario; el payload de 24 h cabe o se divide en shards; ahora/siguiente es correcto en toda la ventana.
- **Puerta C (legal):** licencias de logos y EPG revisadas.
- **Puerta D (regresión):** todos los flujos de 12.3 se comportan igual que la línea base.

Si una puerta falla, el proyecto se detiene en la última fase aprobada; no se avanza “para ver si funciona”.

### 14.6 Riesgos residuales

| Riesgo residual | Nivel | Mitigación |
|---|---|---|
| Cobertura efectiva baja o desconocida | Alto | Medir antes de prometer; estado “Sin EPG”; priorizar canales clave |
| Grabadores bloqueados/geobloqueados | Alto | Múltiples sitios; logs; fallback a servidor local; no reintentar sin límite |
| Licencias de EPG/logos | Alto | Revisión legal; atribución; no redistribuir sin permiso |
| `LabelList` con iconos se comporta mal a 2000 canales | Medio | Spike; carga por ventana; fallback a `RowList` solo si es necesario |
| Payload de 24 h demasiado grande | Medio | Shards por grupo; medir; gzip; no reducir la ventana sin decisión |
| Fuentes arbitrarias sin EPG | Medio | Comportamiento degradado claro; logos desde M3U |
| Cambio de URL en favoritos antiguos | Medio | Conservar favorito; `tvg-id` en nuevos; no inventar asociación |
| Zonas horarias/DST/reloj | Medio | Epoch UTC; `ToLocalTime()`; pruebas de cambio de hora |
| `cachefs` evictado total o parcial | Medio | Comprobar existencia; reconstruir; A/B no garantiza recuperación si se pierde todo |
| Sustitución masiva con igual cantidad | Medio | Indicadores de composición; cuarentena y confirmación |
| Validación de M3U restringe protocolos | Medio | Inventario y regresión por esquema; no filtrar sin verificar |
| Regresión en reproducción/navegación | Alto | Cambios aditivos; pruebas de regresión; no tocar contratos existentes |
| Operación del pipeline | Medio | GitHub Actions; monitorización; `coverage.json`; alertas de fallo |
| Sitios de EPG cambian | Alto | Configuraciones por sitio; reintentos; revisión periódica |

### 14.7 Conclusión de la revisión

**Hechos verificados:** la app es funcional y pequeña; no tiene tests; `LabelList` admite iconos; `tvg-id` y XMLTV comparten el formato `canal@feed` para iptv-org; `guides.json` no trae URLs de descarga y sus 21/40 son potenciales; los JSON/XMLTV completos son inviables en el dispositivo; `cachefs` y el registro tienen límites.

**Hipótesis:** la carga nativa de `LabelList` puede ser suficiente; una ventana de 24 h para 51 canales puede caber en ~500 KB; la cobertura efectiva puede ser aceptable; GitHub Actions/Pages puede ejecutar los grabadores necesarios.

**Decisiones pendientes:** cobertura efectiva, hosting final, comportamiento de `LabelList`, licencias, dispositivos objetivo, UI, umbral de shards, umbrales de composición, inventario de protocolos y política ante pérdida total de `cachefs`.

**Recomendación:** autorizar únicamente la Fase 1 (modelo y generador local) y el spike de la Fase 2a. No iniciar la Fase 3 ni crear infraestructura de publicación hasta medir cobertura efectiva, validar el spike y confirmar el hosting. El plan queda actualizado y no se ha implementado ningún cambio de código.

---

## 15. Arquitectura de actualización dinámica de listas M3U

> Esta sección es una ampliación del plan. No autoriza implementación ni modifica código. Complementa la sección 2.4 y la Fase 1B/4B.

### 15.1 Diagnóstico y objetivo

Hechos comprobados del código actual **[HECHO]**:

- `PlaylistTask.fetchPlaylist()` descarga con `roUrlTransfer.GetToString()` y escribe `cachefs:/pl_<id>.m3u` si el texto parece M3U (`components/PlaylistTask.brs:6-34`).
- Si la descarga no parece M3U, lee la copia cacheada y devuelve `status: "cache"` (`PlaylistTask.brs:16-25`).
- No hay TTL, ETag, `If-None-Match`, `Last-Modified`, hash, validación estructural ni detección de anomalías **[HECHO]**.
- `onPlaylist()` reemplaza `m.channels` y llama a `RenderList()` sin reconciliar foco, orden, pestaña, filtro ni sesión (`MainScene.brs:87-104`).
- `RenderList()` reconstruye todo el `ContentNode` de la lista (`MainScene.brs:140-200`).
- La reproducción depende de `m.current`, `m.playingUrl` y `m.video` (`MainScene.brs:291-340`); una actualización de lista no debe tocarlos.

Consecuencias de una fuente dinámica:

- Un cambio de URL, nombre, grupo, `tvg-id` u orden puede alterar la lista sin que la URL de la M3U cambie.
- Una respuesta HTML, vacía o truncada puede reemplazar una lista buena si no se valida.
- Una caída brusca de canales puede ser legítima o un error del servidor; no debe destruir la última versión válida.
- Reconstruir la lista en cada actualización puede mover el foco, cambiar el orden visible y afectar la experiencia, aunque no la reproducción.

**Objetivo:** mantener la lista razonablemente fresca, cache-first, con última versión válida, validación, cuarentena de anomalías y reconciliación segura, sin interrumpir reproducción, favoritos ni navegación.

**No objetivos:** base de datos, API dinámica, servicio externo nuevo, reescritura del parser, cambio de contratos de reproducción.

### 15.2 Principios y separación de responsabilidades

| Artefacto | Responsable | Versión/caché | No debe provocar |
|---|---|---|---|
| Lista M3U | `PlaylistTask` + módulo de actualización | Slots M3U + metadatos | Descarga de EPG/logos ni cambio de stream activo |
| Catálogo de canales | `MetadataTask` (propuesto) | `catalog.json` versionado | Descarga de M3U |
| Logos | Carga nativa / catálogo | URI + caché nativa | Reconstrucción de lista |
| EPG | `MetadataTask` | `epg.json` versionado | Descarga de M3U |

Reglas:

- Cada artefacto tiene su propio TTL, validación y versión.
- La actualización de M3U no dispara EPG ni logos; solo marca que la identidad de canales puede haber cambiado.
- La actualización de EPG no dispara M3U.
- Un cambio de M3U no cambia por sí mismo la URL de reproducción de la sesión activa.
- Toda integración es aditiva, reversible y tolerante a fallos.

### 15.3 Ciclo de actualización

```text
Inicio / cambio de fuente
        |
        v
Leer slot confirmado (A/B) + metadatos
        |
        +-- no hay copia válida --> descargar en Task
        |                              |
        |                              v
        |                        validar candidato
        |                              |
        |                    +---------+---------+
        |                    |                   |
        |                  valido             invalido
        |                    |                   |
        |                 commit            mantener vacio
        |                    |                   |
        +--------------------+-------------------+
                             |
                             v
              Render inmediato con copia confirmada
                             |
                             v
              ¿edad >= TTL de frescura?
                    |no                    |si
                    v                      v
                 esperar          chequeo en Task (background)
                                           |
              +----------------------------+-----------------------------+
              |                            |                             |
          304 / hash igual            error/timeout                 200 con cuerpo
              |                            |                             |
       actualizar lastCheck          backoff; mantener              candidato temporal
              |                            |                             |
              v                            v                             v
             fin                     ultima valida vigente           validar
                                                                        |
                                          +-----------------------------+-----------------------------+
                                          |                             |                             |
                                       invalido                      anomalia                       valido
                                          |                             |                             |
                                   descartar; backoff          cuarentena; mantener          commit slot inactivo
                                                                        |                             |
                                                                 segunda lectura                 diff + reconciliacion
                                                                        |                             |
                                                                  aceptar o mantener          aplicar en momento seguro
```

El patrón es **stale-while-revalidate**: se muestra la copia confirmada y se revalida en segundo plano. La UI nunca espera la red si existe una copia válida. La red solo actualiza una versión candidata; la copia confirmada permanece hasta que la candidata pase todas las validaciones.

### 15.4 TTL, periodicidad, backoff y límite de frecuencia

Valores iniciales propuestos **[HIPÓTESIS, medir y ajustar]**:

| Parámetro | Valor inicial | Justificación |
|---|---:|---|
| `ttlFresh` | 15 min | Evita consultar al abrir la app varias veces seguidas; las listas públicas no cambian cada minuto |
| `checkInterval` | 60 min | Chequeo condicional en segundo plano; suficiente para listas que cambian como máximo a diario |
| `noValidatorInterval` | 6 h | Si no hay ETag/Last-Modified, cada chequeo descarga el cuerpo completo; 6 h limita el consumo |
| `manualMinInterval` | 60 s | Evita ráfagas si el usuario pulsa Replay repetidamente |
| `backoff` | 2, 5, 15, 30, 60 min | Reintentos acotados; nunca bucle rápido |
| `backoffMax` | 60 min | Techo de espera mientras la fuente falla |
| `jitter` | ±20% | Evita sincronización de reintentos si hay varias fuentes/dispositivos |
| `confirmAfter` | 10 min | Segunda lectura para confirmar un cambio anómalo |
| `maxInFlight` | 1 por fuente | Evita descargas concurrentes y respuestas fuera de orden |

Justificación del coste:

- Una lista de 2,67 MB descargada cada 60 min sin validadores supone ~64 MB/día por fuente; cada 6 h, ~10,7 MB/día. Por eso se separan los intervalos.
- Con ETag/Last-Modified, la mayoría de chequeos devuelven 304 y no transfieren cuerpo.
- El TTL de 15 min es el **mínimo entre chequeos**, no la frecuencia: evita consultas redundantes al inicio y al cambiar de pestaña. El timer periódico es de 60 min.
- Los valores son configurables por fuente (`ttlSec`, `checkSec`, `noValidatorSec` opcionales) y no deben fijarse en el código sin posibilidad de ajuste.

Reglas:

- Solo se actualiza la **fuente activa**; no todas las fuentes a la vez.
- Mientras la app está activa, un `Timer` de `MainScene` dispara el chequeo periódico (60 min por defecto) y lanza la `Task`; no se crea un hilo nuevo por cada comprobación.
- No se descarga la lista al hacer zapping, cambiar foco, cambiar pestaña, abrir el panel ni buscar.
- La consulta al iniciar es: mostrar copia confirmada y, si está caducada, revalidar en segundo plano. Si no hay copia, descargar antes de mostrar la lista.
- Sin validadores HTTP, no se descarga en cada inicio: se respeta `noValidatorInterval` (6 h) aunque `ttlFresh` haya vencido.
- El refresco manual (`Replay`) se conserva: puede forzar el chequeo saltando `ttlFresh`, pero respeta `manualMinInterval` (60 s) y usa el mismo camino de validación.
- Un fallo no cambia el TTL de la última versión válida; solo afecta al próximo intento.

### 15.5 Consulta vs descarga y revalidación HTTP

Se distingue explícitamente:

| Operación | Qué hace | Cuándo |
|---|---|---|
| **Chequeo** | Pregunta si cambió; puede ser 304 o cuerpo | TTL vencido, inicio, refresco manual |
| **Descarga** | Transfiere y valida un cuerpo nuevo | Solo si el chequeo indica cambio o no hay validadores |

Mecanismo propuesto:

1. Guardar `ETag` y `Last-Modified` de la última respuesta 2xx en los metadatos.
2. En el siguiente chequeo, enviar `If-None-Match` y/o `If-Modified-Since` con `AddHeader()` **[VERIFICADO: API disponible]**.
3. Si el servidor responde `304`, no hay cambio: actualizar `lastCheckAt`, no escribir archivo, no renderizar.
4. Si responde `200`, obtener el cuerpo y calcular el hash normalizado. Si coincide con el confirmado, tratar como “sin cambio”.
5. Si no hay validadores, el chequeo implica descarga completa; comparar hash y aplicar TTL largo (`noValidatorInterval`).
6. Usar `AsyncGetToString()` con un `roMessagePort` dentro de la `Task`, no `GetToString()`, porque `GetToString()` descarta cabeceras **[VERIFICADO]**.
7. `roUrlEvent.GetResponseCode()` y `GetResponseHeaders()` permiten leer estado y cabeceras **[VERIFICADO]**; las cabeceras solo están disponibles para respuestas 2xx **[VERIFICADO]**, lo que es suficiente para guardar ETag/Last-Modified de una respuesta válida.
8. Soportar redirecciones, gzip (`EnableEncodings(true)`) y timeout; registrar `GetFailureReason()` para diagnóstico **[VERIFICADO: APIs]**.

**Hipótesis pendiente:** que los servidores de las fuentes respeten `If-None-Match`/`If-Modified-Since` y devuelvan 304. Si no lo hacen, el fallback por hash sigue siendo correcto, solo con más ancho de banda.

Hash normalizado:

- Eliminar BOM, unificar CRLF/LF, quitar espacios finales y líneas vacías.
- Conservar el orden, los `#EXTINF`, `#EXTVLCOPT` y las URLs; no normalizar nombres ni URLs.
- Calcular un hash no criptográfico implementable en BrightScript (por ejemplo, FNV-1a de 32 bits con longitud y conteo de entradas, o dos acumuladores independientes). No se usa para seguridad, solo para detectar cambios.
- Si la versión mínima de Roku expone una función hash adecuada, validarla y preferirla; no se asume.
- Un cambio de ETag con el mismo hash normalizado no genera actualización visual.

### 15.6 Última versión válida y caché segura

No se asume que `cachefs` sea persistente: es RAM si no hay SD y el sistema puede expulsarlo **[VERIFICADO]**. Los slots A/B protegen frente a escrituras parciales mientras la caché siga disponible, pero **no garantizan recuperación si `cachefs` se pierde por completo**.

Se proponen dos slots confirmados, cada uno con su propio sidecar de metadatos, más un índice central:

```text
cachefs:/pl_<id>_a.m3u          contenido confirmado A
cachefs:/pl_<id>_a.json         metadatos del slot A
cachefs:/pl_<id>_b.m3u          contenido confirmado B
cachefs:/pl_<id>_b.json         metadatos del slot B
cachefs:/pl_<id>_meta.json      índice central (puntero y estado)
cachefs:/pl_<id>_candidate.m3u  candidato en validación (nunca confirmado)
```

Metadatos por slot (suficientes para recuperar si el índice central está corrupto):

```json
{
  "schema": 1,
  "sourceId": "d",
  "slot": "a",
  "version": "20261121T060000Z-<hash>",
  "hash": "fnv1a:...",
  "channelCount": 51,
  "validated": true,
  "confirmed": true,
  "confirmedAt": 1795240800
}
```

Índice central:

```json
{
  "schema": 1,
  "sourceId": "d",
  "version": "20261121T060000Z-<hash>",
  "hash": "fnv1a:...",
  "etag": "...",
  "lastModified": "...",
  "channelCount": 51,
  "recentCounts": [51, 50, 52],
  "activeSlot": "a",
  "lastGoodAt": 1795240800,
  "lastCheckAt": 1795240800,
  "failures": 0,
  "nextCheckAt": 1795244400
}
```

Tres situaciones distintas:

| Situación | Qué se conserva | Comportamiento |
|---|---|---|
| Interrupción durante descarga o escritura | Slot activo, su sidecar y el índice central | El candidato o el slot inactivo pueden quedar parciales; se descartan. El slot activo sigue siendo la versión confirmada. |
| Reinicio con archivos de caché disponibles | Slots, sidecars e índice | Se valida el índice y el slot activo; si el índice está corrupto, se recupera con los sidecars. |
| Pérdida completa de `cachefs` | Nada | A/B no ayuda. Se descarga de nuevo; si la red falla, se usa la lista en memoria mientras la app siga abierta; si no, estado vacío controlado. |

Procedimiento de commit:

1. Determinar el slot activo con el índice central y comprobar que el hash del contenido coincide con el hash del índice. Si el índice es válido y el slot coincide, su `activeSlot` manda aunque el otro slot tenga un sidecar más reciente; ese otro slot no está activado. Si el índice falta, está corrupto o el slot activo falta/no coincide, pasar a la recuperación por sidecars.
2. Descargar el cuerpo a memoria y, opcionalmente, a `_candidate` para diagnóstico; **no** escribir todavía el slot confirmado.
3. Validar el cuerpo completo (estructura, parseo, conteo, hash, URLs, composición) y aplicar la política de anomalías.
4. Si es válido y no anómalo, escribir el cuerpo al slot **inactivo**, releerlo y validarlo de nuevo.
5. Si la relectura es correcta, escribir el sidecar del slot inactivo con `version`, `hash`, `validated=true`, `confirmed=false`, `confirmedAt` y `sourceId`. Aún no está activado.
6. Escribir el índice central con el nuevo `activeSlot` y versión. Si esta escritura falla o queda parcial, el índice anterior sigue siendo válido; el slot nuevo se ignora. Si tiene éxito, actualizar el sidecar a `confirmed=true` (mejor esfuerzo).
7. Si el candidato es inválido o anómalo, conservar el activo y registrar el fallo; no borrar la versión anterior. `_candidate` nunca se considera confirmado.
8. Limpiar candidatos antiguos y versiones no activas solo después de que índice y sidecar hayan sido validados.

Recuperación si el índice central está corrupto o el slot activo no está disponible:

1. Si el índice central es válido pero el slot activo falta o no se puede leer, tratarlo como recuperación por sidecars. Leer los sidecars A/B y descartar cualquier slot cuyo sidecar falte, no sea JSON válido, no tenga `confirmed=true` o cuyo hash no coincida con el contenido del slot.
2. Si queda un solo slot confirmado válido, usarlo.
3. Si quedan dos, comparar determinísticamente por generación/version del sidecar (que no depende del reloj) y, si no son comparables, por `confirmedAt`. Usar el mayor.
4. Si el índice central era válido pero la versión recuperada no coincide con la del índice (porque el slot activo faltaba), marcarla como `recovery=true`/provisional: no presentarla como actual, no usarla como base de anomalías y revalidar.
5. Si dos slots son válidos pero no se puede establecer cuál es más reciente (por ejemplo, ambos sidecars han perdido `confirmedAt` y la versión no es comparable), **no presentar ninguno como necesariamente actual**:
   - cargar uno de forma provisional y determinista (slot A) con una marca `ambiguous=true`;
   - no usarlo como base de anomalías ni como versión “fresca”;
   - forzar una revalidación inmediata y, si falla, mostrar un estado de recuperación;
   - el slot A provisional es solo para no dejar la app sin lista, no una afirmación de que sea el más reciente.
6. Si no queda ningún slot confirmado válido, no hay última versión válida disponible: descargar; si falla, usar memoria si existe; si no, estado vacío controlado.

Ventajas y límites:

- No se depende de un rename atómico.
- Una interrupción durante la descarga o escritura deja el slot activo intacto, siempre que `cachefs` no se haya perdido.
- Si `cachefs` expulsa el índice, los sidecars permiten una recuperación determinista; si expulsa un slot, el otro puede servir; si expulsa todo, **no hay recuperación A/B**.
- El registro de Roku no se usa para el contenido; como máximo, un resumen mínimo si se justifica. Nunca la M3U completa.
- El slot anterior se conserva hasta el siguiente commit, lo que permite una reversión manual si una versión válida resulta problemática.

**Pendiente:** validar en dispositivo la semántica de escritura/lectura, el vaciado de buffers, UTF-8 y comportamiento de `cachefs` en la versión mínima de Roku OS. No se asume persistencia ni atomicidad.

### 15.7 Validación y detección de anomalías

#### Validación dura (rechazo)

Rechazar el candidato y conservar la versión anterior si:

- HTTP distinto de 200 (salvo 304, que es “sin cambio”).
- Cuerpo vacío o inferior a un mínimo estructural.
- HTML/JSON de error (`<!DOCTYPE`, `<html`, etc.).
- Falta `#EXTM3U` en la primera línea no vacía (tolerando BOM).
- `ParseM3U()` devuelve 0 entradas.
- Hay `#EXTINF` sin URL siguiente o la última entrada queda truncada.
- URL vacía o malformada: no cuenta como entrada válida y se reporta. No se elimina silenciosamente del contenido para no cambiar el parser/reproductor. No se exige un esquema concreto; el candidato solo se rechaza si no queda ninguna URL aceptable.
- El tamaño recibido no coincide con `Content-Length` cuando este existe y la respuesta no está comprimida ni usa transferencia chunked (en gzip el largo declarado es el comprimido, no el cuerpo descomprimido).
- El parseo lanza error o produce estructuras inválidas.

Protocolos de reproducción:

- El código actual **no filtra esquemas** en `ParseM3U`; `StartPlayback()` pasa `content.url` al nodo `Video` y `GuessFormat()` solo infiere el formato por extensión **[HECHO]**.
- Por tanto, la validación de la M3U **no debe imponer `http://`/`https://` como única regla**. No debe eliminar `rtmp://`, `rtsp://`, `udp://`, `rtp://`, `mms://` ni otros esquemas que una fuente incluya.
- Antes de restringir protocolos, se debe inventariar qué esquemas reproduce realmente la implementación actual en el dispositivo objetivo y añadir una prueba de regresión por cada uno. Hasta entonces, las URLs no vacías se conservan y solo se reporta su esquema; el comportamiento del reproductor no cambia.
- El inventario se hace con URLs de prueba y el `Video` actual, sin modificar `StartPlayback` ni `GuessFormat`. La lista de esquemas admitidos solo se usa para validar si se ha verificado; no se deduce de la documentación ni de una suposición.

#### Anomalía por cantidad (cuarentena)

No reemplazar automáticamente, pero no descartar para siempre:

- Guardar el conteo de las últimas 3 versiones válidas.
- Calcular la mediana.
- Marcar cuarentena si, con una versión anterior de al menos 20 canales:
  - el nuevo conteo cae por debajo del 60% de la mediana **y** la caída absoluta es ≥ 10; o
  - el nuevo conteo supera 3 veces la mediana o suma más de 1000 canales.

Justificación de los umbrales de cantidad:

- La mediana de 3 versiones reduce el ruido de una lectura puntual.
- El 60% con caída absoluta ≥ 10 evita falsos positivos en listas pequeñas.
- Los valores son configurables y deben calibrarse con datos reales; no son una regla de negocio oculta.

Ante una cuarentena por cantidad se aplican las mismas acciones que en la cuarentena por composición: mantener la versión activa, conservar el candidato, registrar estadísticas, repetir la lectura y no borrar la versión anterior.

#### Anomalía por composición (cuarentena)

El conteo por sí solo no detecta una sustitución masiva cuando el total permanece igual. Ejemplo: 100 canales antes y 100 después, con 80 URLs distintas. Hay que analizar la composición usando el diff de la sección 15.8, sin comprobar la disponibilidad de cada stream por red.

Indicadores propuestos **[HIPÓTESIS, calibrar]**:

- `urlRetentionRate = URLs exactas conservadas / max(1, conteo anterior)`.
- `removedRate = streams eliminados / max(1, conteo anterior)`.
- `addedRate = streams agregados / max(1, conteo nuevo)`.
- `tvgIdVariationRate` = IDs `tvg-id` no vacíos que desaparecen o cambian / IDs no vacíos anteriores; si no había IDs, el indicador es N/A.
- `groupRetentionRate = grupos anteriores que siguen presentes / max(1, grupos anteriores)`; si no había grupos, el indicador es N/A.
- `duplicateUrlDelta = duplicados nuevos - duplicados previos`, con `duplicateUrlCount` contando entradas cuya URL aparece más de una vez.

Con una versión anterior de al menos 20 canales, marcar cuarentena si se cumple **cualquiera** de estas condiciones:

- `urlRetentionRate < 0,5` (se pierde más de la mitad de las URLs anteriores; cubre el caso 100→100 con 80 URLs cambiadas);
- `addedRate > 0,5` o `removedRate > 0,5`;
- `tvgIdVariationRate > 0,5`, solo si había IDs `tvg-id` no vacíos;
- `groupRetentionRate < 0,5`, solo si había grupos no vacíos;
- `duplicateUrlCount` supera `max(3, 10% de las entradas)` y además supera `2 * max(1, duplicados anteriores)`.

Reglas:

- La cuarentena por composición conserva la versión activa igual que la de cantidad.
- Se confirma también con una segunda lectura del mismo hash tras `confirmAfter` (10 min); si el hash es idéntico, se acepta como cambio legítimo.
- Un cambio de solo orden no altera la retención de URLs y no debe disparar una falsa anomalía de composición; el orden se trata por separado (15.8).
- No se acepta una sustitución masiva solo porque el conteo permanezca estable.
- No se rechaza automáticamente un cambio legítimo: la confirmación permite aceptarlo.
- Si la fuente cambia en **cada** lectura y nunca se repite el hash, la confirmación automática no es posible; se mantiene la versión anterior hasta una aprobación manual (decisión pendiente) o hasta que el hash se estabilice. No se inventa una confirmación.

Los umbrales anteriores son iniciales y configurables; no son valores definitivos. Deben calibrarse con fixtures y datos reales, y registrar los indicadores en las estadísticas del diff.

**No** se rechaza una lista solo por cambiar mucho: los cambios masivos legítimos se aceptan tras confirmación. **No** se acepta una lista vacía o truncada aunque sea “estable”. **No** se acepta automáticamente una sustitución masiva solo porque el total de canales no cambió.

### 15.8 Diff, identidad y reconciliación

#### Identidad

- **Stream:** `sourceId + url` exacta es la identidad primaria para reproducción y favoritos.
- **Canal:** `tvg-id` identifica un canal/feed, **no** un stream único. Puede haber varios streams con el mismo `tvg-id` y varios feeds por canal.
- **Coincidencia secundaria** cuando la URL cambia:
  1. `tvg-id` idéntico y único en ambas versiones, más nombre/grupo normalizados compatibles.
  2. Nombre normalizado + grupo + país, solo si es único.
  3. Si hay ambigüedad, no se empareja automáticamente.
- Los duplicados de URL se conservan y se reportan; no se colapsan silenciosamente.

#### Diff

Generar estadísticas de:

- agregados;
- eliminados;
- renombrados;
- cambios de grupo;
- cambios de URL;
- cambios de `tvg-id`;
- cambios de `tvg-logo`;
- cambios de `tvg-name`;
- cambios de orden relativo.

El diff calcula también los indicadores de composición de 15.7: retención de URLs, tasas de agregados/eliminados, variación de `tvg-id`, retención de grupos y evolución de URLs duplicadas.

Las estadísticas se guardan en memoria y, opcionalmente, en un JSON pequeño (`pl_stats_<id>.json`) limitado a conteos y ejemplos acotados. **No se guardan en el registro de Roku.**

#### Favoritos

- Nunca se borran automáticamente.
- Si la URL del favorito sigue existiendo, se conserva tal cual.
- Si el canal desaparece, el favorito permanece y se marca como no disponible en la UI; su URL antigua puede seguir funcionando.
- Si la URL cambió, solo se actualiza la referencia cuando la correspondencia es inequívoca: `tvg-id` único, nombre/grupo compatibles, misma fuente y URL antigua ausente. En caso de duda, no se toca.
- Los favoritos antiguos sin `tvgId` solo se recuperan por URL; no se inventa una correspondencia por nombre.
- Los favoritos nuevos guardan `tvgId` opcional (sección 5.4).

#### Sesión y navegación

- No cambiar `m.current`, `m.playingUrl`, `m.video`, subtítulos ni reintentos.
- Si el canal actual desaparece, la reproducción continúa hasta que el usuario cambie o termine. No se detiene ni se reinicia.
- Si la URL del canal actual cambia, la sesión mantiene la URL antigua; la nueva se usará en la próxima reproducción.
- Conservar `m.tab`, `m.filter`, `m.path` y el elemento enfocado por identidad.
- Si el elemento enfocado desaparece, conservar el índice más cercano válido, no volver al principio.
- No reconstruir la lista si no hay cambios reales.

#### Orden

- Si el orden relativo de los canales supervivientes no cambia: aplicar altas/bajas en su posición, una sola reconstrucción controlada.
- Si el orden relativo cambia de forma amplia: conservar el orden visible actual durante la sesión y aplicar el nuevo orden al cerrar/abrir el panel, al cambiar de fuente o en el próximo arranque. Evita saltos abruptos.
- Un refresco manual puede aplicar el orden nuevo tras validación, con confirmación visual discreta.

### 15.9 Protección de la sesión y de la interfaz

Invariantes que la actualización **no** puede violar:

| Invariante | Comprobación |
|---|---|
| No interrumpir reproducción | No llamar a `PlayChannel`, `StartPlayback`, `Zap`, `SeekBy` ni cambiar `m.video` |
| No cambiar URL activa | `m.playingUrl` y `m.current.url` permanecen iguales durante la sesión |
| No cambiar canal seleccionado | No asignar `m.current` por una actualización |
| No perder foco | Reconciliar identidad y `jumpToItem`; si no existe, índice cercano |
| No borrar favoritos | `m.favs` no se reemplaza ni se filtra por la nueva lista |
| No perder última posición | `last_<id>` no se borra ni se reescribe por una actualización |
| No reiniciar la app | No recrear la escena ni el `Video` |
| No aplicar listas inválidas | Solo se aplica una versión confirmada |
| No parpadear | Una sola actualización visual si hay cambios; ninguna si no hay |

`last_<id>` se conserva durante la actualización. Si la URL ya no existe en la nueva versión, `ResumeLast()` no la encuentra al próximo arranque y abre el panel, como hoy; una reconciliación de `last_<id>` por `tvgId` puede evaluarse en Fase 4B sin cambiar la URL de la sesión activa.

Momento seguro para aplicar la UI:

- Si el panel está cerrado: actualizar `m.channels` y no renderizar hasta abrirlo.
- Si la pestaña activa es Favoritos o Fuentes, actualizar el modelo de canales sin reconstruir esa vista; reconciliar al volver a Playlist.
- Si el panel está visible en Playlist y no hay diálogo de teclado activo (`m.top.dialog <> invalid`, no solo la referencia residual `m.dlg`): aplicar una vez y restaurar foco.
- Si hay un diálogo o una operación de edición de fuentes: diferir; guardar `pendingPlaylist` y aplicar al cerrar.
- Si el reordenamiento es amplio: diferir hasta el próximo cierre/apertura del panel.
- Nunca aplicar mientras se está construyendo otra actualización; una sola en vuelo.

### 15.10 Matriz de pruebas y criterios de aceptación

| # | Escenario | Resultado esperado | Invariante protegido |
|---:|---|---|---|
| 1 | Fuente sin cambios | 304 o hash igual; no se escribe slot, no se renderiza, no cambia el foco | Sin cambios innecesarios |
| 2 | Un canal nuevo | Se añade tras validación; foco y reproducción se conservan | Foco/sesión |
| 3 | Un canal eliminado | Se quita de la lista; si estaba reproduciéndose, continúa; favorito permanece | Reproducción/favoritos |
| 4 | Cambio de URL | La lista se actualiza; la URL de la sesión activa no cambia; el favorito solo se actualiza con alta confianza | Sesión/favoritos |
| 5 | Cambio de nombre y grupo | Se actualiza la metadata; foco por URL/`tvgId`; sin pérdida de posición | Navegación |
| 6 | Cambios masivos legítimos | Cuarentena y aceptación tras segunda lectura idéntica; nunca pérdida de la versión anterior | Confirmación/última válida |
| 7 | HTML en lugar de M3U | Rechazo duro; versión anterior intacta; backoff | Última válida |
| 8 | Fuente truncada | Rechazo duro; versión anterior intacta; backoff | Última válida |
| 9 | Fuente vacía | Rechazo duro; versión anterior intacta | Última válida |
| 10 | HTTP 500 | Backoff; versión anterior intacta; sin errores intrusivos | Última válida |
| 11 | Timeout | Backoff; versión anterior intacta | Última válida |
| 12 | DNS fallido | Backoff; versión anterior intacta | Última válida |
| 13 | Desconexión durante descarga | Candidato parcial; nunca se activa; versión anterior intacta | Sin estado parcial |
| 14 | Reinicio durante actualización con caché conservada | Al arrancar se elige un slot confirmado válido; nunca un archivo parcial | Recuperación A/B con caché |
| 15 | Caché ausente o evictada por completo | Descarga; si falla, estado vacío controlado; sin crash; A/B no garantiza recuperación | Degradación, no recuperación total |
| 16 | Usuario reproduciendo mientras cambia | `Video`, URL y estado intactos; sin corte | Reproducción |
| 17 | Usuario navegando mientras cambia | Foco, pestaña, filtro y path conservados; sin parpadeo | Navegación |
| 18 | Favorito de canal eliminado | Favorito conservado; UI lo marca; no se borra | Favoritos |
| 19 | Dos canales con mismo `tvg-id`, URLs distintas | Se tratan como streams separados; no se colapsan ni se cruzan | Identidad de stream |
| 20 | Fuente que cambia frecuentemente con el mismo número de canales | El hash detecta cambios; si la composición es anómala, cuarentena; si nunca se estabiliza, se mantiene la versión anterior y se requiere aprobación manual; sin falsos “sin cambios” | Detección/composición |
| 21 | Igual cantidad (100), pero 80 URLs sustituidas | Cuarentena por baja retención de URLs; versión anterior activa; segunda lectura idéntica confirma | Composición de URLs |
| 22 | Igual cantidad, cambio masivo de `tvg-id` | Cuarentena por variación de `tvg-id`; no sustituir solo porque el conteo es igual | Composición de IDs |
| 23 | Cambio de grupos sin variación de cantidad | Cuarentena si se pierde la mayoría de grupos anteriores; confirmación posterior | Composición de grupos |
| 24 | Duplicación masiva de URLs | Cuarentena; no colapsar duplicados; conservar versión anterior hasta confirmar | Duplicados/identidad |
| 25 | Metadatos centrales corruptos con dos slots confirmados válidos | Elegir por sidecar (`confirmedAt`/generación), no por “más canales”; recuperación determinista | Recuperación determinista |
| 26 | Metadatos corruptos con dos slots confirmados de distinta generación | Elegir la generación confirmada más reciente; si es ambiguo, provisional A + revalidación, sin presentarlo como actual | Ambigüedad segura |
| 27 | Pérdida completa de `cachefs` | No hay recuperación A/B; descargar; si falla, memoria si existe; si no, estado vacío controlado | Pérdida total |
| 28 | Reinicio con caché conservada | Usar versión confirmada validada; no descargar si sigue fresca | Persistencia disponible |
| 29 | URL válida con protocolo admitido por la app distinto de HTTP/HTTPS | La lista se acepta y la URL no se altera; el reproductor mantiene su comportamiento; se documenta el protocolo probado | Protocolos |
| 30 | XMLTV con `start` válido y `stop` ausente | Cuenta como programa; duración desconocida; sin progreso; no se inventa `stop` | EPG sin duración |
| 31 | Manifiesto sin cambios y `refreshAfter` vencido | Se consulta el manifiesto, pero no se descargan catálogo/EPG ni se reconstruye la UI | Sin descargas redundantes |
| 32 | Caché de artefacto ausente o corrupta con versión sin cambios | Se descarga solo para reparar; se valida; la UI solo cambia si los datos difieren | Reparación de caché |

Criterios de aceptación:

- Ninguna respuesta inválida reemplaza la versión válida.
- Ningún 304/hash igual provoca escritura de slot ni `RenderList`.
- Ningún fallo de red borra la versión anterior.
- Ninguna actualización toca `PlayChannel`, `StartPlayback`, `Zap`, subtítulos, `m.current` o `m.playingUrl`.
- Ningún favorito se elimina automáticamente.
- El foco se conserva cuando el elemento existe; si no, se elige el más cercano.
- El reinicio con caché conservada deja un estado confirmado válido (A/B), nunca parcial.
- La pérdida completa de `cachefs` no se presenta como recuperable por A/B: se descarga o se degrada sin crash.
- La recuperación con metadatos centrales corruptos elige por sidecar (`confirmedAt`/generación) y no por número de canales; si hay ambigüedad, no afirma que la versión sea la más reciente.
- El número de solicitudes por fuente respeta TTL/backoff (medido).
- El diff identifica correctamente altas, bajas, renombres, grupos, URLs, `tvg-id`, logo, `tvg-name` y orden en fixtures.
- Las anomalías de composición (retención de URLs, `tvg-id`, grupos y duplicados) se detectan con igual cantidad de canales y pasan por cuarentena/confirmación.
- La validación no elimina URLs por su esquema; solo rechaza vacías/malformadas y conserva el comportamiento del reproductor.
- La EPG con `start` válido y sin `stop` cuenta como programación, sin progreso ni duración inventada.
- Un manifiesto sin cambios y `refreshAfter` vencido no descarga catálogo/EPG ni reconstruye la UI; la caché ausente/corrupta se repara.
- La app sigue funcionando con `cachefs` evictado y sin red, usando memoria si está disponible.

Fixtures y banco de pruebas:

- Servidor HTTP local de prueba con respuestas controladas: 200, 304, 500, HTML, vacío, truncado, lento, cambio de ETag, cambio de contenido sin ETag, manifiesto sin cambios con `refreshAfter` vencido.
- M3U de referencia y variantes para cada escenario, incluidas composiciones 100→100 con 80 URLs sustituidas, cambio masivo de `tvg-id`, cambio masivo de grupos y duplicación de URLs.
- Fixtures de sidecars A/B válidos, corruptos, de distinta generación y con metadatos centrales corruptos.
- Fixtures de protocolos para inventariar los esquemas realmente admitidos, sin asumir HTTP/HTTPS como único. Si el inventario no identifica ningún esquema adicional, la prueba 29 se marca N/A; no se inventa un protocolo.
- Fixtures XMLTV con `start` válido y `stop` ausente.
- Inyección de fallos de archivo para simular slot parcial, pérdida total de `cachefs` y metadatos corruptos.
- Dispositivo real para memoria, foco y reproducción.

### 15.11 Fases y archivos que requerirían modificación

| Fase | Archivos | Cambios | Dependencias |
|---|---|---|---|
| 1B | `components/PlaylistTask.xml` | Campos opcionales: `mode`, `ifNoneMatch`, `ifModifiedSince`, `force`; resultado con `version`, `hash`, `changed`, `anomaly`, `stats`; incluir `source/m3u_update.brs` (y `source/util.brs` si se usan sus helpers) | Fase 1 (parser de atributos) |
| 1B | `components/PlaylistTask.brs` | Fetch condicional en Task, cabeceras, slots A/B con sidecars, validación, hash, cuarentena, stats | `source/m3u_update.brs` |
| 1B | `source/m3u_update.brs` (nuevo) | Normalización, hash, validación estructural, conteo, composición, diff, identidad | Ninguna |
| 1B | `source/util.brs` | Claves de caché/metadatos, tiempo, helpers de URL/identidad | Ninguna |
| 1B | `components/MainScene.xml` | Incluir `source/m3u_update.brs`; sin cambios de layout en esta fase | Fase 1 |
| 1B | `components/MainScene.brs` | Cache-first, programar chequeo, aceptar resultado, reconciliar foco, no tocar playback | `PlaylistTask` |
| 4B | `components/MainScene.xml` | `Timer` periódico y, opcionalmente, indicador de estado | Fase 1B |
| 4B | `components/MainScene.brs` | Refresco periódico, momento seguro, orden diferido, indicador “lista actualizada” | Fase 1B |
| 4B | `source/m3u_update.brs` | Diff/reconciliación de orden y foco; estadísticas acotadas | Fase 1B |
| 4B | `components/PlaylistTask.brs` | Ajustes de backoff, jitter, confirmación de anomalías | Fase 1B |

Sin dependencias nuevas en el paquete Roku. Sin base de datos ni servicio dinámico. `MetadataTask` (catálogo/EPG) permanece separado.

### 15.12 Riesgos y dependencias

| Riesgo | Mitigación |
|---|---|
| Servidores sin ETag/Last-Modified | Hash normalizado; TTL de 6 h; medir ancho de banda |
| Coste de hash/parseo en listas grandes | Todo en `Task`; medir; hash no criptográfico; límites de tamaño |
| Falso positivo/negativo de anomalía de cantidad | Mediana de 3, umbral configurable, segunda lectura idéntica |
| Sustitución masiva con igual cantidad | Indicadores de composición (retención de URLs, `tvg-id`, grupos, duplicados) y cuarentena/confirmación |
| Cambio legítimo masivo bloqueado | Confirmación por segunda lectura; opción manual futura |
| Fuente que cambia en cada lectura | No hay segunda lectura idéntica; mantener versión anterior y requerir aprobación manual o estabilización |
| Metadatos centrales corruptos | Sidecars por slot con versión/hash/estado; recuperación determinista; ambigüedad marcada y revalidación |
| `cachefs` evictado total o parcial | Slots A/B solo si quedan archivos; sidecars para recuperación; si se pierde todo, descargar o usar memoria; no prometer recuperación |
| Restricción indebida de protocolos | No filtrar por esquema; inventariar protocolos admitidos y probar regresión por protocolo |
| Reordenamiento rompe foco | Diferir orden amplio; reconciliar por identidad; pruebas |
| Actualización afecta reproducción | Invariantes explícitos; no tocar `PlayChannel`/`StartPlayback`/`m.video` |
| Favorito con URL obsoleta | No borrar; actualización solo con alta confianza o confirmación |
| Duplicados de `tvg-id` | Identidad por URL; no colapsar; diff por stream |
| Carreras entre chequeos | `maxInFlight=1`; comparar `sourceId` y versión al recibir |
| Metadatos en registro | No guardar contenido; solo resumen mínimo si se justifica |
| Dependencia de APIs Roku | Validar `AsyncGetToString`, cabeceras, 304 y `cachefs` en la versión mínima |
| Fuente desaparece o cambia de dominio | Mantener última versión; backoff; error visible solo en la UI de fuentes |

### 15.13 Decisiones pendientes

| Decisión | Valor inicial propuesto | Estado |
|---|---|---|
| TTL de frescura | 15 min | Pendiente de validar con uso real |
| Chequeo periódico | 60 min condicional | Pendiente |
| Chequeo sin validadores | 6 h | Pendiente |
| Backoff | 2/5/15/30/60 min | Pendiente |
| Umbral de caída de cantidad | <60% de mediana y ≥10 canales | Pendiente |
| Umbrales de composición | Retención de URLs <50%, `tvg-id` >50%, grupos <50%, duplicados >max(3,10%) | Pendiente de calibrar; no son definitivos |
| Confirmación de anomalía | Segunda lectura idéntica a 10 min | Pendiente |
| Fuente que cambia en cada lectura | Mantener versión anterior; aprobación manual o estabilización | Pendiente |
| Actualización de URL de favorito | Solo alta confianza; por defecto no destructiva | Pendiente |
| Reordenamiento | Diferir si es amplio | Pendiente |
| Metadatos por slot | Sidecars con `sourceId`, versión, hash, `validated`, `confirmed`, `confirmedAt` | Pendiente de validar en dispositivo |
| Almacenamiento de metadatos | `cachefs`; resumen mínimo opcional en registro | Pendiente |
| Hash | FNV-1a/ dos acumuladores, sujeto a medición | Pendiente |
| Indicador de actualización | Discreto, no modal | Pendiente |
| Protocolos admitidos | Inventario y regresión por esquema; no asumir HTTP/HTTPS como único | Pendiente |

### 15.14 Conclusión de la ampliación

La actualización dinámica de M3U debe ser **cache-first, validada y reconciliada**, no un simple “descargar y reemplazar”. La última versión válida se conserva hasta que una candidata pase validación y, si hay anomalía de cantidad o composición, confirmación. La reproducción, los favoritos y la navegación quedan fuera del camino de actualización.

**Hechos:** el código actual no valida, no revalida y reemplaza la lista con `RenderList()`; no filtra esquemas de URL; `cachefs` es evictable y el registro es pequeño. Los slots A/B solo protegen mientras la caché siga disponible.  
**Hipótesis:** los validadores HTTP reducirán descargas; los umbrales de cantidad/composición equilibrarán frescura y estabilidad; el hash en Task será suficientemente rápido; los sidecars permitirán recuperación determinista.  
**Pendiente:** validar APIs/cabeceras y `cachefs` en la versión mínima de Roku, medir el coste real, inventariar protocolos, calibrar umbrales y aprobar la política de metadatos por slot.

No se implementa nada en esta fase.

### 15.15 Cambios de esta revisión

| Grupo | Cambio documental | Estado |
|---|---|---|
| A. Caché A/B | Tres situaciones explícitas; sidecars por slot; recuperación determinista por `confirmedAt`/generación; ambigüedad marcada; sin promesa ante pérdida total de `cachefs` | Aplicado; validación en dispositivo pendiente |
| B. Anomalías | Indicadores de composición (URLs, `tvg-id`, grupos, duplicados), cuarentena y confirmación; umbrales marcados como hipótesis | Aplicado; calibración pendiente |
| C. Protocolos | Se elimina HTTP/HTTPS como filtro exclusivo; se conserva el comportamiento del reproductor; inventario de esquemas pendiente | Aplicado; inventario pendiente |
| D. EPG sin `stop` | `start` + título cuentan como programación; duración desconocida separada; sin progreso ni fin inventado; `endKnown`/`unknownDurationCount` | Aplicado |
| E. Descargas | `refreshAfter` solo gobierna el manifiesto; catálogo/EPG solo se descargan por versión nueva, caché ausente o inválida; sin reconstrucción visual si no cambian | Aplicado |
| F. Fase 1/hosting | Fase 1 limitada a modelo, parser, favoritos, mapping y generador local; sin repositorios, workflows, Pages ni publicación; hosting pendiente | Aplicado |
| G. Pruebas | Matriz ampliada a 32 escenarios, con resultado esperado e invariante protegido | Aplicado |

No se modificó código ni se creó infraestructura en esta revisión.

---

## Anexo A. Evidencia de la auditoría local

Archivos leídos íntegramente:

- `manifest`
- `source/main.brs`
- `source/util.brs`
- `components/MainScene.xml`
- `components/MainScene.brs`
- `components/PlaylistTask.xml`
- `components/PlaylistTask.brs`

No se modificó ningún archivo de código durante la auditoría. El único archivo creado/modificado por esta auditoría es este plan.

## Anexo B. Fuentes externas consultadas (2026-11-21)

- `https://github.com/iptv-org/iptv` y `README.md`
- `https://github.com/iptv-org/api` y `README.md`
- `https://iptv-org.github.io/api/channels.json`
- `https://iptv-org.github.io/api/feeds.json`
- `https://iptv-org.github.io/api/logos.json`
- `https://iptv-org.github.io/api/streams.json`
- `https://iptv-org.github.io/api/guides.json`
- `https://iptv-org.github.io/iptv/index.m3u`
- `https://github.com/tv-logo/tv-logos` y `README.md`
- `https://github.com/iptv-org/epg` y `README.md`
- `https://github.com/iptv-org/epg/blob/master/scripts/commands/epg/grab.ts`
- `https://github.com/iptv-org/epg/blob/master/sites/9tv.co.il/9tv.co.il.channels.xml`
- `https://github.com/iptv-org/epg/blob/master/sites/chaines-tv.orange.fr/chaines-tv.orange.fr.channels.xml`
- `https://github.com/iptv-org/epg/blob/master/tests/__data__/expected/epg_grab/base.guide.xml`
- `https://developer.roku.com/dev/docs/labellist`
- `https://developer.roku.com/dev/docs/poster`
- `https://developer.roku.com/dev/docs/rourltransfer`
- `https://developer.roku.com/dev/docs/ifurltransfer`
- `https://developer.roku.com/dev/docs/rourlevent`
- `https://developer.roku.com/dev/docs/ifhttpagent`
- `https://developer.roku.com/dev/docs/roregistry`
- `https://developer.roku.com/dev/docs/file-system`
- `https://developer.roku.com/dev/docs/rodatetime`
- `https://developer.roku.com/dev/docs/optimization-techniques`

## Anexo C. Resumen de datos de la auditoría

| Dato | Valor |
|---|---|
| Canales en `channels.json` | 31.797 |
| Feeds en `feeds.json` | 45.374 |
| Canales con al menos un logo | 30.643 |
| Registros de logo | 35.608 |
| Filas en `guides.json` | 180.680 |
| Canales con alguna fila de guía | 11.771 |
| Filas de guía con `sources` no vacío | 0 |
| `index.m3u` | 2.673.684 B |
| `channels.json` | 7.983.890 B |
| `logos.json` | 5.788.125 B |
| `guides.json` | 25.620.127 B |
| `streams.json` | ~3,9 MB |
| Canales de la fuente principal de la app | 51 |
| Canales con `tvg-id` en esa fuente | 40 |
| Canales con `tvg-logo` en esa fuente | 40 |
| Canales de `m3u.cl` | 19 |
| Canales de `m3u.cl` con `tvg-id` | 0 |
| Canales de `m3u.cl` con `tvg-logo` | 19 |
| Cobertura potencial de mapeo EPG, fuente principal | 21/40 con alguna fila; 19/40 exactos |
| Cobertura efectiva EPG, fuente principal | **No medida**; requiere ejecutar 4.3.1 |
| Cobertura potencial de mapeo EPG, `m3u.cl` | 0 directa; posibles alias manuales, no medidos |
| Caché M3U actual | `cachefs:/pl_<id>.m3u`; sin TTL, ETag ni validación |
| TTL M3U propuesto | 15 min de frescura; chequeo 60 min; 6 h sin validadores |
| Registro máximo oficial actual | 32 KB comprimidos por app |
