# Despliegue EPG en GitHub Actions + GitHub Pages

Proyecto: `streams-roku`  
Fecha: 2026-11-21  
Destino confirmado por el usuario: `robinpalat/streams-roku`  
URL pública prevista: `https://robinpalat.github.io/streams-roku/real/`

No se realizaron commits, push ni publicación pública. El repositorio destino
todavía no existe y Pages no está habilitado.

## 1. Auditoría previa

### Estado del repositorio

- El directorio local **no es un repositorio Git**: no existe `.git` ni remoto
  `origin`.
- No se puede obtener el propietario/repositorio desde Git local.
- El único remoto histórico verificado fue `robinpalat/streams` (rama `main`),
  pero es el repositorio de la playlist y de la web player. Su GitHub Pages ya
  sirve una web en `/streams/`; **no es el destino de este proyecto** y no se
  debe desplegar allí porque reemplazaría esa web.
- El usuario confirmó crear un repositorio nuevo: `robinpalat/streams-roku`.
- La URL se deriva del repositorio, no está escrita a mano en la app.

### Pipeline existente

| Elemento | Estado |
|---|---|
| Generador | `pipeline.build` |
| Fuente M3U real | `pipeline/real/streams.m3u` |
| XMLTV | `pipeline/real/guide-*.xml` (snapshots locales) |
| Grabadores | `iptv-org/epg` mediante `pipeline.grab_epg` |
| Catálogo/EPG/coverage/manifiesto | `pipeline/out/real/` |
| Validador | `pipeline.validate` |
| Servidor local opcional | `pipeline.serve` / `roku-epg.service` |
| Dependencias Python | solo biblioteca estándar |
| Dependencia de grabación | Node.js + npm + checkout de `iptv-org/epg` |
| Config Roku | `pipeline.configure` -> `source/app_config.brs` |
| Consumo Roku | `MetadataTask` -> `latest/catalog/epg` por HTTPS |

Comandos de grabación (comprobados con la documentación de `iptv-org/epg`):

```bash
git clone --depth 1 https://github.com/iptv-org/epg.git /tmp/iptv-org-epg
npm install --no-audit --no-fund --prefix /tmp/iptv-org-epg
python3 -m pipeline.fetch_epg \
  --config pipeline/config/epg_sources.json \
  --epg-repo /tmp/iptv-org-epg \
  --out-dir pipeline/out/xmltv \
  --status pipeline/out/grabber-status.json \
  --generated-config pipeline/out/sources.generated.json
```

`pipeline.fetch_epg` invoca el grabador existente, no lo sustituye. Los grupos
`mi`, `gatotv`, `imjh`, `teleboy` y `extra` son obligatorios; `cinepride`
(`distro.tv`) es opcional y su fallo queda registrado sin bloquear la publicación.

Generación, validación y artefacto público:

```bash
python3 -m pipeline.build \
  --config pipeline/out/sources.generated.json \
  --out pipeline/out
python3 -m pipeline.validate --out pipeline/out/real
python3 -m pipeline.publish \
  --source pipeline/out/real \
  --dest _site \
  --previous .pages-previous
```

## 2. Arquitectura

```text
GitHub Actions (cron cada 6 h / manual)
  -> checkout streams-roku
  -> Python tests
  -> configure --profile production (URL derivada de GITHUB_REPOSITORY)
  -> clone + npm install iptv-org/epg
  -> pipeline.fetch_epg (XMLTV por grupo + estado/errores)
  -> pipeline.build (catálogo/EPG/coverage/latest)
  -> pipeline.validate
  -> fetch de la publicación anterior (coverage)
  -> pipeline.publish (sanitiza, valida, guarda de regresión)
  -> actions/configure-pages
  -> actions/upload-pages-artifact
  -> actions/deploy-pages
  -> verificación HTTPS/HTTP 200/Content-Type/JSON
```

No hay servidor Python en producción. La publicación es estática.

## 3. Estructura pública

Solo se publica:

```text
/real/latest.json
/real/catalog.json
/real/epg.json          (o epg_<grupo>.json si hay shards)
/real/coverage.json
/index.html
```

El catálogo público **elimina `streamMap`**. Se excluyen URLs de streams,
playlists, M3U, configuración local, XMLTV, estado de grabadores y credenciales.
El `coverage.json` público conserva solo métricas y estado de canales; no incluye
`sourceErrors`.

`pipeline.publish` recalcula hashes, tamaños, versión de catálogo y manifiesto.
Nunca copia el directorio de build completo.

## 4. Workflow

Archivo: `.github/workflows/epg-pages.yml`

- `schedule: "0 */6 * * *"` (cada seis horas).
- `workflow_dispatch` para ejecución manual inmediata.
- Permisos mínimos:
  - `contents: read`
  - `pages: write`
  - `id-token: write`
- Concurrencia `pages`, sin cancelar despliegues en curso.
- Usa `GITHUB_TOKEN` implícito de Pages; no hay tokens personales.
- Acciones oficiales de Pages:
  - `actions/configure-pages`
  - `actions/upload-pages-artifact`
  - `actions/deploy-pages`
- Ejecuta las pruebas Python antes de descargar, generar y publicar.
- Sube `grabber-status.json` como artifact de diagnóstico, incluso si falla.

## 5. Integridad y continuidad

Antes de desplegar:

1. `pipeline.validate` verifica manifiesto, JSON, hashes y tamaños.
2. `pipeline.fetch_epg` registra el resultado de cada grabador.
3. Un fallo obligatorio bloquea el build: no se despliega nada.
4. Un fallo opcional se registra y se continúa solo si no hay regresión.
5. `pipeline.publish` compara contra la publicación anterior:
   - rechaza generación vacía;
   - rechaza caída de canales con programas por debajo del 85 %;
   - rechaza caída de programas por debajo del 75 %;
   - rechaza perder canales que antes tenían programación.
6. El artefacto se escribe en un directorio temporal y se valida antes de
   reemplazar el destino local.
7. Si el workflow falla antes de `deploy-pages`, GitHub Pages conserva la última
   versión publicada.
8. El despliegue no se ejecuta si fallan tests, descarga, build o publicación.

Diagnóstico de grabadores:

```text
pipeline/out/grabber-status.json
```

Se publica como artifact de Actions, no en Pages.

## 6. Configuración Roku

`pipeline.configure` tiene dos perfiles:

```bash
# Producción: URL derivada del repositorio
python3 -m pipeline.configure --profile production \
  --repo-url https://github.com/robinpalat/streams-roku.git

# Desarrollo: servidor LAN opcional
python3 -m pipeline.configure --profile development
```

Producción escribe:

```text
source/app_config.brs
  DefaultMetaBase() = https://robinpalat.github.io/streams-roku/real/
  DefaultMetaSourceMatch() = robinpalat/streams
```

El `sourceMatch` sigue identificando la fuente M3U; no se modifica la playlist.
En CI no se pasa `--repo-url`: se usa `GITHUB_REPOSITORY`, y se verifica que la
URL final conserve el prefijo `/streams-roku/real/`.

`JoinUrl()` ya está probado con la URL con prefijo de repositorio; no se asume
que una ruta relativa funcione igual que una absoluta.

### Migración de instalaciones existentes

`LoadSources()` reemplaza automáticamente un `s.meta` local
(`http://192.168.*`, `http://10.*`, `127.*` o `localhost`) por la nueva base
HTTPS cuando la app de producción apunta a Pages. No cambia URLs M3U, favoritos,
`PlayChannel`, `StartPlayback`, zapping ni reproducción.

### Compatibilidad MetadataTask

`MetadataTask` ya usa HTTPS, certificados, `latest.json` versionado, caché local
y recuperación desde caché si el manifiesto no está disponible. GitHub Pages
sirve los `.json` con `Content-Type: application/json`; el workflow lo verifica
después del despliegue. El manifiesto incluye hashes y tamaños para auditoría de
los artefactos.

## 7. Habilitar GitHub Pages

Pasos exactos, después de crear el repositorio y subir el proyecto (con
autorización expresa):

1. Crear `robinpalat/streams-roku` en GitHub. No reutilizar
   `robinpalat/streams`.
2. Subir el contenido del proyecto a la rama predeterminada `main`.
3. Abrir **Settings > Pages**.
4. En **Build and deployment > Source**, elegir **GitHub Actions**.
5. Si el repositorio es privado, comprobar que el plan permite Pages; no cambiar
   la visibilidad ni permisos existentes.
6. Abrir **Actions > EPG GitHub Pages > Run workflow** para la primera ejecución
   manual.
7. Esperar a que termine el job `build` y luego `deploy`.
8. Comprobar:
   - `https://robinpalat.github.io/streams-roku/real/latest.json`
   - `https://robinpalat.github.io/streams-roku/real/catalog.json`
   - `https://robinpalat.github.io/streams-roku/real/epg.json`
   - `https://robinpalat.github.io/streams-roku/real/coverage.json`
9. Regenerar e instalar el paquete Roku de producción.

Si Pages no está habilitado, `actions/configure-pages` falla con un error de
Pages; la corrección es el paso 4, no añadir tokens.

## 8. Frecuencia, caché y actualización

- Cron cada 6 horas en UTC.
- `workflow_dispatch` ejecuta inmediatamente sin esperar al cron.
- Los workflows programados solo se ejecutan en la rama predeterminada.
- `latest.json` incluye `refreshAfter`; `MetadataTask` respeta esa marca y usa
  caché local. GitHub Pages/CDN puede servir una versión anterior brevemente
  durante la propagación.
- La app no descarga el catálogo/EPG si la versión no cambia.
- No se borra la publicación anterior por un fallo de grabador o de validación.

## 9. Desarrollo local

El servidor local sigue disponible solo como herramienta de desarrollo:

```bash
python3 -m pipeline.build --source real --out pipeline/out
python3 -m pipeline.serve --dir pipeline/out --port 8001
python3 -m pipeline.configure --profile development
```

Diferencias:

| | Desarrollo | Producción |
|---|---|---|
| URL | `http://IP:8001/real/` | `https://robinpalat.github.io/streams-roku/real/` |
| Servidor | Python local | GitHub Pages estático |
| Config | `--profile development` | `--profile production` |
| Paquete | Puede usar LAN | Debe usar Pages |

El perfil de desarrollo no cambia `s.meta` local a Pages. El perfil de producción
sí migra URLs LAN antiguas cuando la base generada empieza por `https://`.

## 10. Regenerar el paquete Roku

```bash
python3 -m pipeline.configure --profile production \
  --repo-url https://github.com/robinpalat/streams-roku.git
/tmp/opencode/bsc/node_modules/.bin/bsc --create-package true --diagnostic-level error
cp out/streams-roku.zip streams-roku.zip
```

Paquete actual: `build_version=18`, 29 archivos, 2.031.727 bytes, SHA-256
`22c4345440d37921586078dfb519780426500d764a5666969d2f29d5da830e0e`.

## 11. Diagnóstico

| Síntoma | Causa probable | Acción |
|---|---|---|
| 404 en `latest.json` | Pages no habilitado o fuente no es GitHub Actions | Settings > Pages > Source: GitHub Actions |
| 503 tras deploy | Propagación de Pages | Reintentar tras unos minutos |
| Workflow falla en grabador | Sitio caído/bloqueado | Revisar `grabber-status`; un obligatorio bloquea |
| Regresión de cobertura | Pérdida de programas/canales | Revisar fuentes; Pages conserva versión anterior |
| `Content-Type` incorrecto | Artefacto no subido o ruta incorrecta | Revisar upload/deploy y verificación |
| Roku sin actualizar | Caché/versión | Reabrir app; comprobar `latest.json` y versión |
| Roku sin EPG | URL/config antigua | Reinstalar paquete producción y abrir fuentes |

El workflow verifica HTTPS, HTTP 200, `application/json` y JSON válido de los
cuatro endpoints después del despliegue.

## 12. Publicación y datos

- No se publican streams, M3U, `streamMap`, XMLTV, credenciales, tokens,
  configuración local ni datos personales.
- El catálogo público solo conserva nombre, logo, `epgId`, canal/feed.
- La EPG contiene metadatos de programación; antes de hacer público el sitio se
  deben revisar los términos de las fuentes XMLTV. Los snapshots locales ya
  advertían que su redistribución requiere revisión.
- El repositorio de playlist/web player `robinpalat/streams` no se toca.
- No se cambió la visibilidad ni los permisos de ningún repositorio.

## 12.1 Pruebas locales ejecutadas

| Prueba | Resultado |
|---|---|
| Python pipeline | 64 pruebas, 0 fallidas |
| BrightScript puro | 62 aserciones, 0 fallidas, 6 pendientes |
| BrighterScript | 0 errores |
| Build/validate/publicación local real | OK |
| Public artifact sin `streamMap` | OK |
| Guarda de regresión y conservación local | OK |

La suite incluye pruebas de URL de producción/desarrollo, prefijo del repositorio,
catálogo/EPG/manifiesto, ausencia de archivos sensibles, fallo de grabador,
generación defectuosa, conservación de la publicación anterior y estructura del
workflow.

## 13. Estado de entrega

Implementado y probado localmente:

- workflow, descarga, configuración de perfiles, build, validación, publicación
  sanitizada, guardas de regresión, pruebas y documentación.

Pendiente de acciones externas, con autorización:

1. Crear `robinpalat/streams-roku`.
2. Subir los archivos (commit/push) cuando se autorice.
3. Habilitar Pages con origen GitHub Actions.
4. Ejecutar el workflow manualmente.
5. Verificar la URL pública y regenerar/instalar el paquete Roku.

No se publicó nada ni se modificó el repositorio remoto.
