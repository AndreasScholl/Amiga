# Zwischenbericht C – fließender Sternübergang (`starFlow` = 1)

Sicherung vor C: `bak7\`. Schalter = 0: Programm-Hunks Byte für Byte gleich dem Stand vor C (`d_base8`).

## Geändert (alles unter `starFlow`, `stars3d.i`, eine Farbe in `scroller.s`)
- **Förderband** (`s3Spawn`, `s3FlowAdd`): Jeder neue Stern liegt in Welttiefe 19 Viertel-z hinter dem vorigen. Das erste Band beginnt bei 2400, direkt hinter der hinteren Schicht.
  - Nie näher als die Grenze des fernsten Bandes minus 256.
  - Weiter als `S3ZMAX` warten die Sterne geparkt, höchstens bis 4060.
  - Ein Stern, der verschwindet, wird gelöscht. Nachgelegt wird nach dem Frame, solange das Band Platz hat.
- **Umgewandelte Sterne** liegen irgendwo in ihrem Farbband: 220–400 / 400–600 / 700–1650 / 1650–2400.
  - Der vordere Bereich beginnt bei 220 statt 200, damit die beiden Blend-Schleifen ohne Test bleiben (`S3ZSAFE`).
  - Bildort und seitliches Tempo bleiben gleich.
- **Farben:** fernste `$0003`. Orange-braun `$0842` wechselt 50 bzw. 100 Frames nach dem Blend auf `$0852` und dann `$0952`.
- **Bandgrenzen nach dem Blend:** 600 / 1000 / 1400 / 1800 / 2500 / 3300.
- **`S3ZMAX` 3700:** Dahinter wird nicht gezeichnet. Das spart 2,4 KB Tabelle.

## Messwerte

| Seed | Peak gesamt | Umwandlung / Blend max | leere sichtbare Fächer (+30…+500) | Farbwechsel/Frame max |
|---|---|---|---|---|
| default | 113 362 | 109 712 | 0 Frames | 6 |
| 00001234 | 114 082 | 102 194 | 0 | 6 |
| c0ffee11 | 114 040 | 103 096 | 4 Frames | 6 |
| 5bd1e995 | 116 554 (wie vorher) | 114 804 | 0 | 7 (1 Frame) |
| 9e3779b9 | 113 620 | 102 936 | 0 | 6 |
| 00c0ffee | 114 130 | 102 906 | 3 Frames | 6 |

- **Vorher (gleiche Messung):** leere Fächer in 415–420 von 471 Frames, Farbwechsel bis 10 pro Frame.
- **Sichtbare Fächer** heißt: 500 bis zur Grenze des fernsten Bandes, in 250er Schritten.
  - Jenseits davon liegt das kaum sichtbare `$0003`-Band. Dort füllt sich der Bereich 2500–3500 erst ab etwa +80…+100 Frames, weil das Band erst läuft, wenn die Zahl der Sterne auf 190 gefallen ist. Früher füllen würde zusätzliche Sterne im Blend kosten, genau in den teuersten Frames.
  - Das Fach 250–500 ist manchmal leer, auch vorher. Nahe Sterne verlassen den Bildschirm seitlich, bevor sie so nah sind.
- **Gleichmäßigkeit 1250 bis zur Bandgrenze:** vollstes zu leerstem Fach höchstens 1,6–2,1 : 1. Vorher gab es leere Fächer.
- **Sterne im Feld:** 144–190 statt fest 190. Das Band legt nur so viele nach, wie es mit gleichem Abstand unterbringt. Deshalb liegen die Frame-Spitzen in der Elite meist niedriger.
- **Speicher:** 771 320 B (vorher 773 500). Flugaufzeichnung unverändert.

## Pixelvergleich
- **Wechsel-Frame und die Frames danach:** pixelgleich mit dem Stand vorher (default 5227–5240, 5bd1e995 5550–5560), also Positionen unverändert.
- **In den Umwandlungs-Frames davor** weichen 2–12 Pixel ab, in 1–5 Zeilen: Defender-Sterne, die dort einen Frame früher oder später weitergerückt sind.
  - Ursache: Die Streuung kostet ~1k Zyklen mehr pro Umwandlungs-Frame, und damit verschiebt sich, in welcher Zeile die Defender-Sterne ihre neue Position bekommen.
  - Das gab es vorher genauso, nur in anderen Zeilen.

## Montage
- `img\stars10s_starFlow.png` und zum Vergleich `img\stars10s_vorher.png`: default, Frames 5227 bis 5727 in 100er Schritten.
- Das erste Bild ist im Harness schwarz, weil der Umschalt-Frame dort noch nicht fertig gezeichnet ist.

**Nur in WinUAE zu beurteilen:** wie die Sternfarben wirken, vor allem wie dunkel `$0003` ist.
