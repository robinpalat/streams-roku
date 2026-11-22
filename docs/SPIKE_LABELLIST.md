# Spike de listas y geometría de logos (pendiente de hardware)

> El nombre del archivo se conserva por historial. La app ya **no usa
> `LabelList`** para la lista de canales.

## Diagnóstico

`LabelList` solo ofrece `HDListItemIconURL`/`HDListItemIconSelectedURL`; no
expone una propiedad documentada para ancho, alto, modo de escalado o caja del
icono. Con logos de dimensiones originales muy distintas se producen tamaños
desiguales y superposición.

La solución implementada es `MarkupList` + `ChannelItem`:

- fila de 44 px y separación vertical de 4 px;
- caja de logo fija 58×36 en `[8,4]`;
- `Poster` con `loadDisplayMode="limitSize"`;
- `FitLogoInBox()` aplica `contain`, centra y nunca excede la caja;
- placeholder uniforme para ausencia/error;
- el texto comienza en x=76 y el fondo ocupa toda la fila.

## Preparación

1. Copia `images/logo_placeholder.png` a `pipeline/out/spike/logo.png`.
2. Genera una lista de 50, 500 o 2000 elementos:

```bash
python3 -m pipeline.spike_m3u --count 2000 \
  --logo-base http://IP-DEL-PC:8000/spike/logo.png \
  --out pipeline/fixtures/spike_2000.m3u
```

3. Sirve `pipeline/out` con `python3 -m pipeline.serve --dir pipeline/out --port 8000`.
4. Añade la URL `http://IP-DEL-PC:8000/spike_2000.m3u` como fuente en la app.
5. Prueba además con logos cuadrados, horizontales extremos, verticales,
   pequeños, grandes, PNG transparente y URLs 404.

## Medición

- ¿Hay solapamiento entre filas o logos?
- ¿Todos los logos caben en 58×36 sin deformación?
- ¿Están centrados horizontal y verticalmente?
- ¿El foco/selección mantiene la misma geometría?
- Memoria, texturas, tiempo de apertura y scroll en 50/500/2000.
- Peticiones de imagen y carga diferida.

## Estado

La geometría está validada por XML y matemáticamente por `FitLogoInBox` y tests
BrightScript. **No hay Roku físico en este entorno**, por lo que el spike visual
sigue pendiente y no se declara resuelto en pantalla.
