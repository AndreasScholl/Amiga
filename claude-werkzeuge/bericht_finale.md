# Elite-Finale – Bericht

Alle Messungen im Harness, 6 Seeds (default, 00001234, c0ffee11, 5bd1e995, 9e3779b9, 00c0ffee), 9300 Frames: jeder Seed läuft damit bis über die Treffer hinaus.

**Schalter in switches.i:** alle 1.
- fixQmarks = 1, starPal2 = 1, escortMux = 1, drumSeq = 1, showdownLean = 1.

**Speicher:**
- Ausgangswert 775 228 B, jetzt **773 500 B** (chip 349 096, other 424 404).
- Flugaufzeichnung: 58 122 B, also unter 64 KB.

**Frame-Spitzen, alle Schalter 1:**

| Seed | Spitze | bei Frame |
|---|---|---|
| default | 115 872 | 6556 |
| 00001234 | 116 510 | 6900 |
| c0ffee11 | 115 888 | 6648 |
| 5bd1e995 | 116 554 | 5571 |
| 9e3779b9 | 115 936 | 7132 |
| 00c0ffee | 116 296 | 8052 |

- Es gibt keine Stalls. Die Sim ist vor dem Abspielstart fertig.
- S3CHK: 0 fehlerhafte Frames.

**Backups (Scratchpad):**
- `bak1\`: vor Teil 1.
- `bak2\`: vor Teil 2.
- `bak3\`: vor Teil 3, inklusive abgen.py und abflame.i.
- `bak4\`: vor Teil 4, inklusive sfx.i. In `bak4\LSP\` liegen die LSP-Dateien, aber schon mit Patch. Mit musDrums = 0 sind sie inhaltlich identisch zum Original.
- `bak5\morph_before_lean.i`: vor Teil 5.

**Schalter-0-Prüfung** (Programm-Hunks ohne Debug-Info verglichen, `hunkcmp.ps1`):
- starPal2 = 0 gleicht dem Stand nach Teil 1: 6400 Frames kostengleich, Bilder pixelgleich.
- escortMux, drumSeq und showdownLean alle = 0 gleichen dem fertigen Stand nach Teil 2 Byte für Byte.
- drumSeq = 0 bei escortMux = 1 ist byte-identisch zum Stand nach Teil 3.
- showdownLean = 0 weicht nur in 2 Bytes ab. Das ist die unter escortMux verkleinerte Aufzeichnungsgröße.

## Teil 1 – Fragezeichen (`fixQmarks`)
Unverändert gegenüber dem letzten Bericht.
- DEFTEST trifft je Seed 12–21 Zeichen mehr.
- Der Laser-Teil ist unverändert.
- Im default-Seed kann ein letztes „??“ in der oberen Reihe übrig bleiben.

## Teil 2 – Sternfarben (`starPal2`)

**Deine Rückmeldung:** Die Sterne werden höchstens orange, und das erst kurz vor dem Verschwinden; die meiste Zeit sind sie blau.

**Ursache:** Die Bandgrenzen lagen fast alle im Nahbereich. Ein Stern war die meiste Zeit seines Lebens in den fernen Bändern (dunkel, blau, braun).

**Neu:**
- Nach dem Wechsel wandern die Grenzen nach außen: hell bis z 700, hellorange bis 1100, orange-braun bis 1500, grün bis 1800, braunrot bis 2700, blau bis 3200, darüber dunkel.
- Ein neuer Stern läuft damit durch alle 7 Farben, jede mit einem eigenen Stück Weg.
- Die Grenzen wandern 6 Viertel-z pro Frame, also schneller als vorher.

**Farbanteile** (Pixel im unteren Bildbereich, default):

| Frame | dunkel | blau | braunrot | grün | orange | hell | weiß |
|---|---|---|---|---|---|---|---|
| 5800 | 92 | 68 | 48 | 28 | 52 | 84 | 124 |
| 6400 | 44 | 80 | 108 | 132 | 84 | 56 | 44 |
| 6800 | 40 | 96 | 96 | 156 | 132 | 60 | 48 |
| 7000 | 40 | 116 | 152 | 80 | 76 | 108 | 36 |

- Zum Vergleich der alte Stand bei 6000: Die warmen Farben (orange, hell, weiß) lagen bei ~15 %, jetzt sind es 30–40 %.

**Rechenzeit:** Die zusätzlichen Doppel-Plane-Sterne kosten. Ausgeglichen ist das, indem in der schnellen Schleife das Schleifenende auch im Mehr-Plane-Zweig steht (−10 Zyklen pro Stern). Die Bilder sind dabei gleich.

**Ehrlich:** Direkt nach dem Wechsel (~5350–5650) bilden die vielen gleichzeitig neu erzeugten Sterne eine Wolke. Die wechselt gemeinsam dunkel → blau → braun. Ab ~5700 ist alles gemischt.

**Montage:** `img\pal3.png`.

## Teil 3 – Begleitflug mit Multiplexing (`escortMux`)

**Abwurf und Zündung:**
- Abwurf im ENTRY (Halbtakt-Raster): Frames 12, 18 und 24 des Anflugs, solange der Jäger noch oben rechts ist.
- Die Torpedos fallen kalt und langsam: Geschwindigkeit 20/256, Beschleunigung 1/256.
- Der Motor zündet frühestens nach einem Takt, und erst wenn das Schiff samt Nachbrennerkette sicher darunter ist.
- Spätestens nach 4 Takten wird gezündet; diese Fälle zählt der Harness als „spät“. Ergebnis: 0 späte Zündungen.

**Einschläge:** Exakt wie vorher, also 7198, 7234 und 7270 im default-Seed. Jeder Torpedo hat dafür sein eigenes Trefferalter.

**Break:** 383 Frames, also 7,7 s vor dem ersten Treffer (war 2,9 s).
- Die Escort-Liste ist auf 15 Takte gekürzt: Weave 3, Barrel 4, Knife 3, Move 3, Victory-Roll 2.

**Multiplexing:**
- Die Nachbrennerkette bleibt immer stehen; es gibt keinen Übergang mehr zur kleinen Flamme.
- Torpedo k teilt sich Sprite k (0..2) mit Kettenglied k, oben und unten.
- Bilder kommen aus `abImg` (Düsenart), Flackern aus der Tabelle der Kette (`morphChFlk`), Farben aus der Nachbrennerpalette.
- Pro Sprite zwei Bilder. Zwischen Ende und Start bleibt mindestens eine freie Zeile, für die Steuerwörter.

**Garantie in der Sim:**
- Die Sim kennt für jedes Kettenglied den möglichen Zeilenbereich: Weganteil × f (0,25–1,15), Radius 7.
- Kommt ein Torpedo-Glow „seinem“ Glied näher als 2 Zeilen plus Lücke, wird nur dieser Glow weggelassen und gezählt. Die Raute bleibt sichtbar.
- Ergebnis: **25 Glow-Frames weggelassen**, alle beim Vorbeidonnern des Jägers (6881–6905).
- Die Abspielseite musste nie etwas weglassen (0).
- Im Harness (`Seq.cs` MuxChk): **0 Überlappungen**, kleinste Lücke 26 Zeilen, bis zu 2 Bilder pro Sprite, 373 Zwei-Bild-Sprites.

**Rechenzeit:**
- Kopierschleife mit festem Abstand und Tabellen statt mulu.
- Die Sim stoppt eine Spur früher (Zeile 218 statt 222). Sie hat ohnehin über 1992 Frames Vorsprung.

**Speicher:**
- Sprite-Puffer 1056 statt 544 B. Ausgeglichen durch den Wegfall von morphSprImg/morphSprMake/morphColTorp/morphColMix und durch die Aufzeichnung: 62 KB reserviert, 58,1 KB davon genutzt.

**Montage:** `img\final_mux.png`.

## Teil 4 – Schlagzeug (`drumSeq`)

**Ablauf:**
1. **Break** (nur der des Breaks, nicht der Nachbrenner im PASS): Die Kanäle 0–2 (Bass, Begleitung, Melodie) blenden über 5,5 s aus. Das Schlagzeug auf 3 spielt weiter.
   - Technik: LSP schreibt seine Lautstärken nach `lspVol`; `musVolOut` gibt sie skaliert aus.
2. **Übergabe** am nächsten Taktanfang: LSP stoppt.
   - Die Kanäle der Musik werden stumm und ihr DMA aus.
   - Den DMACON-Patch-Byte (`m_dmaconPatch`) löscht ab da `dsTick` jeden Tick und setzt ihn nur für eigene neue Noten. Timer B schaltet also nichts Altes wieder ein.
3. **Eigener Sequencer** (`drumseq.i`, aus der Partitur erzeugt mit `drumgen.ps1`):
   - Datenumfang: 8 Instrumente, 6 Taktmuster, die 128 Takte des Songs.
   - Er spielt genau die Takte, die der Song an dieser Stelle spielen würde: gleiche Samples, Perioden und Lautstärken.
   - Kanäle: Kick, Snare und Tom auf 0, Hi-Hats auf 2. 1 und 3 bleiben für die Effekte frei.
   - Die Daten liegen im Fast-RAM-fähigen Datenbereich.
4. **Pause:** der letzte Schlag vor dem ersten Treffer ist still. Mit dem Treffer-Takt geht es weiter.

**Gemessen** (Audio-Simulation im Harness, `Aud.cs`, default):

| Ereignis | Frame |
|---|---|
| Ausblenden ab | 6816 |
| LSP aus, Übergabe | 7105 |
| Pause | 7177–7200 |
| Wieder an | 7201 (Treffer bei 7199) |

- Vor dem Break sind die Kanalpegel mit und ohne Schalter identisch (680 Messfenster).

**Hörproben** (vereinfachtes Paula-Modell, nur Musik, ohne Effekte; Frames 6400–7700):
- vorher: `snd_drumseq0.wav`
- nachher: `snd_final.wav`

## Teil 5 – Showdown (`showdownLean`)

**Umschalten:** sobald der Jäger weg ist. Bedingung: Warten begonnen, plus 24 Frames, und er wird nicht gezeichnet.

**Danach:**
- Keine Aufzeichnung wird mehr gelesen, es gibt keine Flamme und keine Kette.
- Die Torpedos fliegen geradlinig von ihrer Position zu ihrem Logopunkt und kommen genau zu ihren alten Trefferzeiten an.
- Sie sind reine Blob-Sprites (abImg, R 1–2), ohne Linien.
- Der Motorton des Jägers verklingt weiter wie in der Aufzeichnung: Lautstärke × 512 / (512 + t), 30 → 18. Kanal 3 läuft mit, solange es laut genug ist.

**Frei werdende Puffer als Overlay:**

| Overlay | Inhalt | Größe | frei ab |
|---|---|---|---|
| `sdOvl` / `sdOvlLen` | morphRcp + morphRec | 4 400 + 63 488 B | morphRecFree (letzter Treffer) |
| LSPMusic (Partitur) | – | 41 611 B | musState = MS_DRUMS (Übergabe) |

**Rechenzeit-Tabelle** (default, ganz ähnlich in allen 6 Seeds):

| Abschnitt | vorher max / Ø | jetzt max / Ø |
|---|---|---|
| Break → Warten | 110 286 / 92 579 | 110 480 / 92 773 |
| Warten → Umschalten | 82 628 / 76 474 | 82 822 / 76 668 |
| mager, bis 1. Treffer | 84 532 / 77 265 | 82 856 / 75 902 |
| mager, Treffer | 83 456 / 75 833 | 81 440 / 74 280 |
| 200 Frames danach | 79 630 / 73 252 | 77 766 / 71 344 |

Spielraum im Showdown: ~34k Zyklen bis zur 117k-Marke.

## Was nur in WinUAE zu beurteilen ist
- Wie die Sternfarben wirken, vor allem die Farbwolke direkt nach dem Wechsel.
- Wie Abwurf, Zündung und die gemeinsamen Sprites aussehen, und ob echte Sprite-DMA sie so sauber zeigt wie das Modell.
- Klang: Ausblenden, Übergabe, Pause und das Weiterspielen auf 0/2 (Stereobild!).
  - Die WAVs zeigen nur die Musik.
  - Der CIA-Takt (50,0 Hz) gegen den VBL (50,08 Hz) kann die Pause um 1–2 Ticks verschieben.

## Offene Punkte
- Teil 1: Vereinzelt bleibt ein „??“ übrig.
- Teil 3: 25 Glow-Frames weggelassen, während der Jäger durchrauscht. Die Rauten bleiben sichtbar.
- Teil 5: Die Overlays sind nur definiert; noch nutzt sie keine Szene.
