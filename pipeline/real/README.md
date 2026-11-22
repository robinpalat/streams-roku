# Datos EPG reales (local)

Snapshot local de la lista `robinpalat/streams` y de XMLTV obtenidos con
`iptv-org/epg` el 2026-11-21. Los XMLTV originales no se publican. Solo los JSON
compactos generados se despliegan en GitHub Pages mediante el workflow; revisar
los términos de cada fuente antes de publicar. Ver
`docs/DEPLOYMENT_GITHUB_PAGES.md`.

## Fuentes XMLTV

| Sitio | Canales | Estado |
|---|---|---|
| `mi.tv` | Mega, 13C, 24 Horas, América TV, CDM | 5 con programas; Space se obtuvo de gatotv |
| `gatotv.com` | Cinecanal Pacífico, Historia, Space Panregional | 3 con programas |
| `i.mjh.nz` (Pluto/Plex/Roku) | BBC Drama, Cine Friki, Cine Western, CinePride, Crimen & Historia, Love Nature, Stingray | 5 con programas; 2 sin programas |
| `teleboy.ch` | DW Español, TVE Internacional | 2 con programas |
| `tv.nu` | Stingray Classica | 5 programas |
| `reportv.com.ar` | Eurochannel | 8 programas |
| `distro.tv` | CinePride | ERROR de DNS; se usó la alternativa sin programas |

`CinePride.us@SD` quedó con 0 programas: no se inventó programación. Los
horarios son los publicados por cada sitio; la app los muestra en hora local del
dispositivo.

## Reproducir

Los archivos `channels-*.xml` documentan los `site_id`/`xmltv_id` usados. Los
guías se generaron con el checkout local de `iptv-org/epg`:

```bash
python3 -m pipeline.grab_epg --epg-repo /tmp/opencode/iptv-org-epg \
  --channels pipeline/real/channels-mi.xml \
  --out pipeline/real/guide-mi.xml --days 1
```

(Repetir por grupo). Después:

```bash
python3 -m pipeline.build --source real --out pipeline/out
```

El directorio de snapshots permanece local. La publicación de producción usa
los XMLTV descargados en `pipeline/out/xmltv` y el artefacto sanitizado de
`pipeline.publish`.
