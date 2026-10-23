# Elite-Endkampf als Film (`recV2`, `cineFight`)

Stand 23.10.2026. Alle Werte stammen aus dem Harness, über 6 Seeds gemessen. In WinUAE habe ich nichts gesehen.

Sicherung vor diesem Umbau: `bak9\` (alle Quellen, dazu `d_base9`).

## Schalter (switches.i)

| Schalter | Stand | Inhalt |
|---|---|---|
| recV2 | 1 | neues Format der Flugaufzeichnung |
| cineFight | 1 | Endkampf mit echtem Flugmodell (neue Datei `cine.i`) |

## 1. Flugaufzeichnung im neuen Format (`recV2`)
- **Segmente:** 1, 2, 4 oder 8 Frames. Dazwischen rechnet das Abspielen in einer geraden Linie (16.16).
- **Prüfung:** Die Simulation schaut 8 Frames voraus. Sie wählt das längste Segment, bei dem jeder Zwischenframe höchstens 1 px vom echten abweicht.
- **Was interpoliert wird:** Schiffspunkte, Luke, Torpedos (Ort und Richtung der Flamme), Ton und Sterntempo.
- **Ergebnis:** Der alte Flug braucht 29,4 KB statt 49,4 KB. Der neue, fast doppelt so lange Flug (3313 Frames) braucht 54,9 KB.
- **Speicher:** Gesamt 771 812 B wie vorher. Chip-RAM: 348 932 B (vorher 349 824 B). Der neue Code liegt in einem eigenen Abschnitt, der nicht im Chip-RAM stehen muss.

## 2. Flugmodell (`cine.i`)
Das Schiff fliegt wie ein echter Jet. Es gibt keine Federn und keine Kurvenkurven mehr.
- **Kräfte:** Der Auftrieb steht senkrecht auf der Flugbahn und neigt sich mit der Querlage. Dazu kommen Schwerkraft (echte Größe: 72 Einheiten Schiffslänge = 18 m) und Schub bzw. Luftbremse entlang der Bahn.
- **Grenzen der Maschine:** Rollrate bis 90°/s, weich auf- und abgebaut. g-Last 0,25–4 g, Aufbau etwa 5 g/s. Längs bis 0,3 g.
- **Pilot:** Er fliegt Zielpunkte an, kritisch gedämpft mit etwa 9 s Periode. Er folgt der Bahn des Drehbuchs und lenkt nur über Querlage und Ziehen. Ab und zu macht er eine kleine Korrektur mit der Hand.
- **Nase:** Sie zeigt entlang der Bahn, beim Ziehen etwas nach oben in den Auftrieb (Anstellwinkel 1,5° je g).
- **Rolle:** Wie bei einem echten Piloten: erst die Flächen gerade legen, dann hochziehen (+2 g), entlastet mit 0,3 g rollen, danach abfangen. Ergebnis: Das Schiff steigt um 30 Einheiten und kommt zurück, seitlich weicht es um ±6 Einheiten ab.

## 3. Drehbuch (Takte zu 24 Frames)

| Abschnitt | Takte | Inhalt |
|---|---|---|
| Anflug | 10 | aus dem Looping von rechts oben, im Sinkflug, leicht schneller als wir, 60° links geneigt; rollt aus und setzt sich vor uns |
| Formation | 4 | ruhig vor und unter uns |
| Kurven | 8 + 8 + 6 | weite, langsame Kurve nach rechts, dann nach links, zurück in Linie (Querlage bis etwa 35°) |
| Rolle | 7 + 1 | siehe oben |
| Absenken | 8 | tief in die Mitte unter das Logo (195 voraus, 66 tiefer): man sieht von oben |
| Ruhe | 4 | die Kontur der Bucht ist zu sehen |
| Luke auf | 2 | zwei Klappen, seitlich angeschlagen, öffnen auf etwa 100°, weich beschleunigt; ein Klack |
| Start ×3 | je 4 | Torpedo fährt auf einem Aufzug 0,8 s aus der Bucht, wird nach oben abgestoßen (Klack, das Schiff gibt etwas nach und fängt sich), gleitet 0,36 s kalt, zündet und beschleunigt mit etwa 6 g zum Logo |
| Luke zu | 3 | |
| Atempause | 2 | |
| Break | 6 | volle Querlage 80° rechts, 6 g, Nachbrenner; verliert in der Kurve Fahrt und ist an uns vorbei |

- **Dauer:** Der Endkampf vom Anflug bis zum Break dauert 69 Takte, das sind 33 s. Vorher waren es 20 Takte.
- **Treffer:** wie bisher 16 Takte nach dem Break. Das Abschwellen der Musik, das Schlagzeug und die Pause hängen am Break und laufen deshalb einfach später.

## Messwerte (6 Seeds)
- **Simulation:** fertig bei Frame 4090–4574. Das Abspielen beginnt frühestens bei 5087. Keine Stalls, keine Fehler.
  - Die Simulation rechnet jetzt bis Rasterzeile 230 statt 218. Sie hält nach dem echten Strahl an, ihr längster Schritt endet etwa bei Zeile 250.
  - Deshalb meldet der Harness vor dem Abspielen einzelne Frames bis 123,6k. Das ist Restzeit, kein Ruckeln.
- **Frame-Spitze beim Abspielen:** 121,8k–122,9k, immer beim Start der Torpedos.
  - Je Seed liegen etwa 100 Frames über 117k und 11–15 über 120k.
  - Geruckelt hat es bisher ab etwa 132k im Harness.
- **Aufschlüsselung des teuersten Frames:**
  - Sterne 47k, Logo-Farbmaschine 15,5k
  - Linien 13k Rechnen + 11k Zeichnen (35 Linien)
  - Glow-Sprites 8–11k
  - Dekoder 5,5–8k, Luke 4k (8 Linien)

## Optimierungen ohne sichtbare Änderung
- **Logo-Farbmaschine:** zwei Zeilen pro Durchlauf. Die Copperwerte sind Byte für Byte gleich, in 6 Frames verglichen.
- **Kantenschleife:** Die Register pro Linie werden nicht mehr gesichert.
- **Dekoder:** Schritt-Schleife je 8 Werte, Entpacken ohne Schleife.

## Nur in WinUAE zu beurteilen
- ob der Flug schwer und echt wirkt (Kurven, Rolle, Absenken, Break);
- wie die Luke und das Ausfahren der Torpedos wirken: von hinten oben sieht man die Klappen schmal, fast von der Kante;
- ob es beim Start der Torpedos ruckelt (Frames bis 123k);
- Länge und Tempo des ganzen Endkampfs.
