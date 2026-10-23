# Elite – C (Sternübergang) und B (Abschuss) umgesetzt

Stand 22.10.2026. Alle Werte stammen aus dem Harness. In WinUAE habe ich nichts gesehen.

## Schalter (switches.i)

| Schalter | Stand | Grund |
|---|---|---|
| sprTest | 0 | wie gewünscht, die Glows laufen wieder |
| spr8 | 1 | unverändert (abgenommen) |
| starFlow | 1 | alle Prüfungen bestanden, Details unten und in `zwischenbericht_C.md` |
| launchSeq | 1 | Treffer-Frames bei allen 6 Seeds gleich, Spitze ≤ 117k |
| starCam | 1 | nur das Schub-Tempo der Sterne; Spitze 116 954 |

- **Schalter = 0, Programm-Hunks Byte für Byte verglichen:**
  - alle drei auf 0 = Stand vor C (`d_base8`);
  - nur starFlow auf 1 = Stand nach C;
  - starFlow + launchSeq auf 1, starCam auf 0 = gleicher Stand ohne starCam.
- **Backups:** `bak7\` (vor C), `bak8\` (vor B).

## Messwerte gesamt (alle Schalter wie oben)
- **Frame-Spitze:**
  - 6 Seeds: höchstens **116 954**, bei 5bd1e995 Frame 5571 (Blend + Start des Abspielens; vorher 116 554).
  - Alle anderen Seeds ≤ 114 300.
- **Speicher:** **771 812 B** (vorher 773 500): chip 349 824, sonst 421 988.
- **Flugaufzeichnung:** **58 122 B vorher → 49 414 B jetzt**, bei allen Seeds gleich. Die Torpedos stehen erst ab Sim 1416 statt 1068 drin.
- **Treffer (Abspiel-Frames):** **1919 / 1955 / 1991** bei allen 6 Seeds, wie vorher. Break-Phase bei Sim 1536 unverändert, Stalls 0.
- **Rechenzeit je Abschnitt (default, max/Ø):**

  | Abschnitt | vorher | jetzt |
  |---|---|---|
  | Hereinkommen | 112,1k / 97,5k | 102,0k / 88,4k |
  | Vorführen | 109,9k / 100,2k | 98,8k / 89,9k |
  | Zielen | 105,3k / 97,4k | 96,8k / 89,9k |
  | Ausstoß | 102,9k / 92,9k | 107,9k / 94,2k |
  | Begleitflug | 100,8k / 94,5k | 109,1k / 101,5k |
  | Break | 106,4k / 88,4k | 114,3k / 95,6k |

  Bis zum Ausstoß wird es billiger, weil noch keine Torpedos unterwegs sind. Danach teurer, weil die Torpedos jetzt in diesen Abschnitten fliegen und vorher schon weiter weg waren.
- **Eingesparte Zyklen durch Wegfall des Multiplexing:** Beim Abspielen praktisch keine.
  - `morphSprFrame` mit 3 brennenden Torpedos: vorher 10,9–11,5k (davon `morphMxSpr` 5,8–6,4k), jetzt 10,9–11,4k. Das Sortieren entfällt, dafür werden jetzt 7 statt 4 Sprites gefüllt.
  - In der Sim entfallen `simMxRange` und der Abstandscheck: Sim-Spitze 61 842 → 61 522 Zyklen pro Frame.

## C – fließender Sternübergang
Siehe `zwischenbericht_C.md`.
- **Förderband:** neue Sterne alle 19 Viertel-z, ab 2400, weiter weg geparkt.
- **Umgewandelte Sterne** über ihr Band gestreut (220–400 / 400–600 / 700–1650 / 1650–2400).
- **Farben:** `$0003` … `$0fdb`. Orange-braun geht nach dem Blend in 2 s über `$0852` auf `$0952`.
- **Bandgrenzen:** 600 / 1000 / 1400 / 1800 / 2500 / 3300. `S3ZMAX` 3700.
- **Prüfungen:**
  - Leere sichtbare Fächer: vorher in 415–420 von 471 Frames, jetzt in 0 Frames (4 Seeds) bzw. 3 und 4 Frames (c0ffee11, 00c0ffee).
  - Farbwechsel pro Frame höchstens 6, ein einziger Frame mit 7 (vorher bis 10).
  - Der Wechsel-Frame ist pixelgleich.
  - Montage: `img\stars10s_starFlow.png`, zum Vergleich `img\stars10s_vorher.png`.

## B – Abschuss bei voller Fahrt (launchSeq)

| Abschnitt | Sim | default | Inhalt |
|---|---|---|---|
| Hereinkommen | 1056–1175 | 6335–6454 | Weg unverändert, keine Abwürfe |
| Vorführen | 1176–1247 | 6455–6526 | großer Bogen: ±70 Einheiten seitlich, 30 hoch und wieder runter, bis 50° zusätzliche Schräglage, Schub steigt beim Steigen |
| | 1248–1319 | 6527–6598 | schwere Fassrolle (3 Schläge, weich ein- und auslaufend) |
| Zielen | 1320–1391 | 6599–6670 | Ziel unter der Logomitte. Erst über die Hälfte des Weges hinaus, dann ein Viertel zurück, dann genau hin, je ein Drittel des Blocks. Feder dabei steifer und weniger gedämpft, die Nase ±5°. Danach ruhig |
| Ausstoß | 1416 / 1440 / 1464 | 6695 / 6719 / 6743 | Torpedo springt nach oben aus der Oberseite (verliert pro Frame 3/16 des Schwungs). Schiff zuckt nach unten und zur Kamera und federt schwer nach. Dumpfer Stoß (Abwurf-Geräusch). Schiffslinien 3 Frames im Farbblitz `$0ffa` |
| Zündung | 14 Frames nach dem Ausstoß | z. B. 6710 | Blitz, Flackerkette, Beschleunigung 10 statt 6 |
| Begleitflug | bis 1535 | bis 6814 | wie vorher: Bewegung nach oben links, die Rolle, dann der Break |

- **Kein Zappeln:** Die Pilot-Korrekturen (Jitter) sind im Begleitflug abgeschaltet. Die Federn bleiben schwer (3/70), nur beim Zielen weicher.
- **Klappe: nicht gebaut.** Die Oberseite (Maskenbit 0) ist in Sim 1380–1490 in keinem Frame sichtbar, weil die Kamera fast auf Höhe des Schiffs liegt. Eine Klappe dort sähe man nicht. Stattdessen gibt es den Farbblitz per Copper.
- **Sprites:**
  - Kette auf 0–3, Torpedos auf 4/5/6, jeder ein eigenes Sprite mit `abImg`, der Flackertabelle der Kette und den Farben des Afterburners (25–27, 29–31).
  - Multiplexing, Abstandscheck und Notfallregel sind unter launchSeq weg.
  - Im Showdown werden 4–6 abgeschaltet, dort laufen die Blobs wie vorher auf 0–2.
- **starCam:** Im Begleitflug folgt die Sterngeschwindigkeit weich dem Schub (256 + (Schub − 192)/2, ein Achtel pro Frame). Außerhalb davon wie vorher.
  - Den vertikalen Fluchtpunkt habe ich nicht gebaut. Er bräuchte eigene Löschlisten pro Puffer und Rand-Reserve, und die Spitze bei 5bd1e995 liegt schon bei 116 954.
- **Montagen:**
  - `img\ls_show_aim_cop.png`: Vorführen und Zielen, alle 12 Frames.
  - `img\ls_eject1.png`, `ls_eject2.png`, `ls_eject3.png`: jeder Ausstoß samt Zündung Frame für Frame.

## Nur in WinUAE zu beurteilen
- der Flugstil: ob es schwer und souverän wirkt;
- das Flackern der Torpedos auf eigenen Sprites;
- der Farbblitz;
- die Sternfarben, vor allem wie dunkel `$0003` ist;
- das Schub-Tempo der Sterne.

Memory ist nicht aktualisiert.
