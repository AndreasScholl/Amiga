# Elite – Teil A umgesetzt, Plan für B und C

Stand: 22.10.2026. Alles ist im Harness gemessen. In WinUAE habe ich nichts gesehen.
Sicherung der Quellen vor den Änderungen: `bak6\` im Scratchpad.

## A. 8 Sprites (Schalter `spr8` = 1)

### Befund pro Bildbereich (heute, `clistElite`)

| Bereich | Zeilen | Planes | DDFSTRT/STOP | DIW | BPLCON1 | Modulo |
|---|---|---|---|---|---|---|
| Kopf der Liste | bis $1f | aus ($0200) | $28/$d8 | $2081/$2cc1 | 0 | 0/0 |
| Sterne oben | $20 bis Logo | 4: Sterne 1–3 (s3-Puffer) + Spielfeld 4 (bufA/B) | wie oben | wie oben | 0 | 0/0 |
| Logo-Band (Teil von `clist`, per Sprung) | Logo-Start bis -Ende (wandert mit dem Wippen) | 4: Logo 1–3 (logoPadded) + Spielfeld 4 | wie oben | wie oben | 0 | logoPlaneMod 0 / 0 |
| Sterne unten (`eliteMid`) | Logo-Ende bis $12b | 4: Sterne 1–3 + Spielfeld 4 | wie oben | wie oben | 0 | 0/0 |
| darunter | ab $12c | aus | – | – | – | – |

- **Warum $28:** Das Spielfeld des Asteroids-Teils ist 368 px breit (46 Bytes). Die ersten 32 px liegen hinter dem linken Rand, 16 px hinter dem rechten, damit Objekte ohne Clipping aus dem Bild fliegen können (Kommentar in `asteroids.s` Zeile 86). Das Logo wurde auf 46 Bytes aufgefüllt, weil es sich den Modulo mit dem Spielfeld teilt. Die Sterne benutzen dieselbe Breite (`S3LI = 46`).
- **Wer davon abhängt:** Logo, Sterne und Spielfeld brauchen nur die Zeilenbreite von 46 Bytes, nicht den frühen Fetch. Die verdeckten Spalten sieht man ohnehin nicht.
- **Scrolltext/horizontaler Versatz in der Elite:** keiner. Der Balken mit den BPLCON1-Wellen und die TV-Liste liegen in `clist` unterhalb von gameTop. `clistElite` springt nur für das Logo-Band in `clist` und kommt am Logo-Ende zurück. Deshalb braucht keine Zeile $30.
- **Schreibzugriffe in der Elite** (Harness-Wache auf den Logo-Teil, alle 6 Seeds): Danach werden nur noch die Wartezeilen geschrieben (Wippen). Logo-Zeiger, Planes und Modulo bleiben unverändert.

### Umsetzung (alles unter `spr8`)
- `clistElite`: DDFSTRT $38, DDFSTOP $d0. Geholt werden 40 Bytes pro Zeile, Modulo +6 (`ELMOD = li-40`) auf allen Zeilen.
- Jeder Plane-Zeiger der Elite +4 Bytes (`ELOFS`): Sterne oben und unten, Spielfeld.
- Logo im Teil von `clist`: Im ersten Frame von `clistElite`, in `s3Flip`, werden die Logo-Zeiger mit +4 neu gesetzt (`updateLogoPointers`) und `logoPlaneMod` um 6 erhöht. Das passiert zur selben Zeit wie der vorhandene Rücksprung-Patch. Vorher geht es nicht, weil im Frame davor noch `clist` läuft.
- **Speicher:** Der neue Code braucht 16 B. Ich habe sie beim Puffer der Flugaufzeichnung abgezogen (`62*1024-16`, belegt sind 58 122 B). Gesamt **773 500 B**, unverändert.
- **Schalter = 0:** Programm-Hunks Byte für Byte identisch mit dem Stand davor.

### Nachweis
- **Pixelvergleich:** Ich habe beide Programme in denselben Frames gerendert, im Harness-Bild nach Bildschirmposition. Ergebnis:
  - Seed default: 223 von 224 Bildern pixelgleich, von 5226 bis 9280 jede 40. Frame, dazu die Treffer-Frames.
  - Die übrigen 5 Seeds: je 112 von 112 pixelgleich.
  - Einzige Abweichung: 2 px in Zeile $20 im Umschalt-Frame 5227. Das ist ein Fehler des Harness: Er zeichnet diesen Frame schon mit `clistElite`, auf der echten Hardware läuft dort noch `clist`.
  - Der erste echte `clistElite`-Frame (5228) ist pixelgleich. Der Harness rechnet dabei mit dem Zeitpunkt der CPU-Schreibzugriffe gegenüber dem Strahl.
- **Frame-Spitze über 6 Seeds:** 116 554, identisch zu vorher. Der Harness rechnet die freigewordenen Bitplane-DMA-Zyklen nicht ein, real wird es also eher etwas besser.
- **Was der Harness nicht abbildet:** die Zeitfenster der Sprite-DMA. Ob Sprite 4–7 wirklich sauber kommen, zeigt nur WinUAE.

### Sprite-Test (`sprTest` = 1, steht jetzt so)
- Alle 8 Sprites als Balken über Logo-Band und Sterne, Zeilen $22–$128, 40 px Abstand, je Paar eigene Farben, alle 16 Zeilen eine weiße Linie.
- Speicher: Der Test braucht keinen eigenen Speicher mehr. Er benutzt den Puffer der Glows, die im Test ohnehin aus sind. Dafür beginnen alle 8 Sprites auf denselben Datenzeilen: Über den Balken 0–6 stehen 7 bis 1 Zeilen Muster ohne Bedeutung, das ist so gewollt.
- Der Test-Build hat 773 700 B, weil der Test-Code dazukommt. Das liegt unter dem früher lauffähigen Stand von 775 228 B.
- Im Umschalt-Frame kostet der Aufbau einmal 122,8k. Das ist ein einzelner langer Frame, nur im Test.
- Bild: `img\sprtest8.png`.
- Nach dem Test `sprTest = 0` setzen. Dann laufen die Glows wieder.

---

## B. Torpedo-Abschuss (Schalter `launchSeq`) – nur Plan

### Ausgangslage (Sim-Frames ab Play-Start; Seed default: +5279)
- Phasen heute:
  - ENTRY 1056–1175 (5 Schläge, oben rechts herein);
  - ESCORT 1176–1534;
  - BREAK 1535;
  - WAIT 1632;
  - Treffer 1919 / 1955 / 1991 (= 7198 / 7234 / 7270).
- Abwürfe heute 12, 18 und 24 Frames nach Beginn von ENTRY, also gleich beim Hereinkommen. Deshalb wirkt es zu früh und ohne Absicht.
- Sterne: Ab ENTRY Höchsttempo (`morphVzMax`), kein Abbremsen. Die Afterburner-Kette ist mit `escortMux` dauernd an. Das Leitbild „volle Fahrt“ ist also schon erfüllt und bleibt so.

### Zeitplan (Sim-Frame / Frame bei Seed default; 1 Schlag = 24 Frames)

| Abschnitt | Sim | default | Inhalt |
|---|---|---|---|
| Hereinkommen | 1056–1175 | 6335–6454 | Weg oben rechts unverändert (abgenommen), aber ohne Abwurf |
| Vorführen | 1176–1319 (6 Schläge) | 6455–6598 | weich hoch/runter, Fassrolle, Messerlage, Kurve mit Schräglage. Schub wechselt 160–256, das Triebwerk spielt mit |
| Zielen | 1320–1391 (3 Schläge) | 6599–6670 | Korrekturen bei 1320, 1332, 1344 mit Überschwingen, ab ~1360 ruhig unter dem Logo, Nase leicht zum Logo hoch |
| Klappe auf | 1392–1403 | 6671–6682 | Klack auf dem Schlag 1392, optional Farbblitz per Copper |
| Ausstoß 1/2/3 | 1416 / 1440 / 1464 | 6695 / 6719 / 6743 | Stoß senkrecht nach oben aus der Klappe, dann kalt als Linien-Raute. Das Schiff zuckt 2–3 px zurück, Feder ~16 Frames. Dumpfer Stoß |
| Zündung 1/2/3 | ab 1440 / 1464 / 1488 | 6719 / 6743 / 6767 | erst wenn der Torpedo über der Afterburner-Kette steht (in der Sim geprüft), spätestens +2 Schläge. Blitz, Flackerkette, dann rast er zum Logo |
| Klappe zu | 1488–1499 | 6767–6778 | Klack |
| Begleitflug | 1500–1534 | 6779–6813 | 1,5 Schläge |
| Break mit Boom | 1535 | 6814 | unverändert, 384 Frames = 7,7 s vor Treffer 1 |
| Treffer | 1919 / 1955 / 1991 | 7198 / 7234 / 7270 | exakt wie heute |

- **Flug nach der Zündung:** etwa 480 Frames (9,6 s). Die Ankunft ist wie heute über das Alter je Torpedo festgelegt (`tp_hit`), nur mit neuem Start.

### Umsetzung (Plan)
- **Sim:**
  - neue Manöverliste unter `launchSeq`;
  - zusätzlich ein vertikales Weben und ein Zielmanöver `MV_AIM`: Ziel springt in halben Schlägen +12 / −6 / 0 px, Feder etwas weicher, damit es sichtbar überschwingt;
  - Ausstoß in `morphTorpFire` von unten nach oben verlegt, mit Anfangsgeschwindigkeit nach oben, die schnell abklingt;
  - Rückstoß als Stoß auf die vorhandene Positionsfeder.
- **Klappe:**
  - Die Aufzeichnung bleibt bei 16 Punkten. Die Punkte kommen paarweise (links/rechts). Die Oberseite ist das Dreieck Nase 0 / hinten oben 1 und 2, die Kanzel 11–13 liegt darauf.
  - Die 4 Klappenlinien werden beim Abspielen aus den aufgezeichneten Bildpunkten berechnet:
    - Ecken als feste Mischungen von 1, 2, 12, 13 (zwischen Kanzel und Hinterkante);
    - „oben“ als (P1 − P3)/15;
    - Öffnungswinkel aus der festen Frame-Nummer.
  - Kosten in der Aufzeichnung: 0 Bytes.
  - Gezeichnet wird nur, wenn die Oberseite sichtbar ist (Maskenbit 0).
  - Die Alternative wären 2 zusätzliche Punkte: +2 B pro Frame, also ~4 KB. Davon rate ich ab.
- **Sprites mit 8 Sprites (A in WinUAE bestätigt):**
  - Kette auf 0–3 wie heute, Torpedos fest auf 4 / 5 / 6, Sprite 7 frei (z. B. Blitz beim Ausstoß);
  - Farben der Paare 4/5 und 6/7 gleich der Torpedo-Palette;
  - Multiplexing und der Abstandscheck in der Sim entfallen. Das spart im Begleitflug ~6k Zyklen pro Frame (`morphMxSpr` heute 5,9–6,4k).
- **Sprites ohne 8 Sprites:**
  - der heutige `escortMux`-Weg;
  - kalte Phase ohne Sprite;
  - Zündung erst, wenn die Sim den Abstand garantiert;
  - „ein Frame aussetzen“ als Notfall, gezählt im Harness, Ziel 0.
- **Ton:** Klack und Stoß aus dem vorhandenen Abwurf-Geräusch (`RB_DROP`) mit eigener Tonhöhe und Länge, Zündung wie heute (`RB_IGN`).

### Kosten (Schätzung)
- **Zyklen:**
  - Klappe ~2–3k pro Frame, nur in 1392–1499. Grundlage: `set_line` ≈ 410 pro Linie, plus Rechnung.
  - Ausstoß/Rückstoß in der Sim < 0,5k.
  - Mit 8 Sprites unterm Strich ~3k Gewinn.
  - Ohne 8 Sprites muss Platz geschaffen werden. Kandidat: `logoColorEngine`, die 15,5k pro Frame kostet und auch läuft, wenn sich nichts ändert.
- **Speicher:**
  - Code +0,6–0,9 KB.
  - Mit 8 Sprites fallen Mux-Code und Sim-Check weg, etwa −1 KB.
- **Flugaufzeichnung:** Torpedos stehen erst ab 1416 statt 1068 drin, rund 350 Frames × 3 Torpedos weniger. Das sind mehrere KB weniger als heute 58,1 KB, also klar unter 64 KB.

### Risiken
- Das Budget in ENTRY/Begleitflug ist eng: heute 115,8–115,9k, Grenze 117k.
- Ohne 8 Sprites bleibt es beim Multiplexing mit Abstandscheck.
- Die Klappe ist nur genähert (affin aus Bildpunkten). Bei nahem Schiff und starker Perspektive kann sie leicht „schwimmen“. Das muss man in WinUAE ansehen.
- Ob Zielen und Korrekturen absichtlich wirken, ist Geschmack, also WinUAE.

### Optional: Sterne folgen dem Schiff (Verfolger-Kamera)
- **Schub-Tempo:** Sterngeschwindigkeit an den Schub koppeln, < 0,1k pro Frame. Empfohlen.
- **Fluchtpunkt vertikal:** Basis des Puffers pro Frame um dy × 46 verschieben, ~0,2k pro Frame. Die Löschliste braucht dann die Basis ihres Frames, und am oberen und unteren Rand braucht es Reserve. Machbar, mittlerer Aufwand.
- **Fluchtpunkt horizontal:** nur in 8-px-Schritten über die Basis möglich. Feiner ginge nur über BPLCON1, und das würde auch das Spielfeld verschieben, weil Plane 2 und 4 dieselbe Verzögerung haben. Nicht empfohlen.
- **Parallaxe auf und ab** (Versatz vor der Division): passt nicht zur Log-Darstellung, ~60 Zyklen pro Stern, also ~11k. Zu teuer.
- **Rollen:** viel zu teuer.

---

## C. Sterne: fließender Übergang (Schalter `starFlow`) – nur Plan

### Ursache, belegt
Histogramm der Sterne über die Tiefe (Viertel-z, Fächer zu 250), Seed default, Umschaltung bei Frame 5227:

| Frame | Sterne | 0–1250 | 1250–1750 | 1750–2500 | 2500–4000 |
|---|---|---|---|---|---|
| 5227 | 320 | 248 | **0** | 72 | **0** |
| 5300 | 191 | 126 | 9 | 56 | 0 |
| 5400 | 190 | 21 | 30 | **4** (1750–2250: 0) | 135 |
| 5500 | 190 | 17 | 0 | 63 | 110 |
| 5600 | 190 | 5 | 46 | 102 | 37 |

- Beim Wechsel sind alle 320 Sterne umgewandelte Defender-Sterne in 4 festen Tiefen (256 / 512 / 1024 / 2048, je ±1/8). Zwischen 1150 und 1800 ist nichts, jenseits von 2300 auch nichts.
- Im Blend (5227–5300) fliegen ~130 Sterne seitlich hinaus und werden nicht ersetzt, bis 190 erreicht sind (`S3NLIVE`).
- Ersatz entsteht nur bei 2950–3973, und zwar dann, wenn Sterne verschwinden. Die nahen Schichten verschwinden gemeinsam, also kommen ~130 neue Sterne fast gleichzeitig. Es entsteht eine Schale mit einer **Lücke** zur alten hinteren Schicht (Frame 5400: 1750–2250 leer), und die Schale wandert als **Welle** nach vorn.
- **Gemeinsamer Farbwechsel:**
  - Die Grenzen der Farbbänder wandern 5340–5540 durch die Schale.
  - Später kreuzt die Schale die Grenzen gemeinsam. Beispiel: Band braun-rot 42 → 85 → 122 Sterne in 5400 / 5500 / 5550, Band orange-braun 22 → 54 in 5600 → 5700.
- Deine Vermutung stimmt also.

### Lösungsweg
1. **Neue Sterne wie auf einem Förderband:**
   - Jeder neue Stern bekommt die Welttiefe des vorigen plus einen festen Abstand, ~21 Viertel-z (= Tiefenbereich / 190). Er liegt aber nie näher als die hinterste belegte Tiefe.
   - Weiter weg als `S3ZMAX` wartet er „geparkt“. Das kann der Code heute schon.
   - Damit ist die Dichte hinter dem Feld ab dem ersten Ersatz gleichmäßig: keine Schale, keine Lücke, keine Welle.
   - Die Logs des vorberechneten Sterns werden auf die neue Tiefe umgerechnet (2 Additionen aus `s3ZTab`).
2. **Umgewandelte Sterne über ihr Farbband streuen statt ±1/8:**
   - vorne 200–400, zweite 400–600, dritte 700–1650, hinten 1650–2400;
   - 100 Viertel-z Abstand zur nahen Grenze, damit die Schleifen im Blend ohne Test bleiben (`S3ZSAFE`).
   - Positionen und Bewegung im Wechsel-Frame bleiben gleich: Bildort und seitliches Tempo der Schicht sind unverändert, die Vorwärtsbewegung ist im ersten Frame 0.
   - Ab dem ersten Frame ist 200–2400 lückenlos, und das Förderband schließt bei 2400 direkt an.
3. **Ausdünnen 320 → 190** bleibt wegen des Budgets. Es trifft hauptsächlich die nahen Sterne, die seitlich hinausfliegen, und hinterlässt keine Tiefenlücke.
4. **Farbwechsel verteilt:** Bei gleichmäßiger Dichte kreuzen die Sterne die Bandgrenzen gleichmäßig über die Zeit. Auch das Wandern der Bänder erzeugt dann nur ein stetiges Rinnsal statt Schübe.

### Farben, Vorschlag (fern → nah)

| Index | heute | neu | Helligkeit (0,3R + 0,59G + 0,11B) |
|---|---|---|---|
| 1 dunkel (fernstes) | $0114 | **$0003** (kaum sichtbar) | 0,3 |
| 2 Defender-Blau (hintere Schicht) | $0125 | $0125 | 2,0 |
| 4 braun-rot (dritte) | $0631 | $0631 | 3,7 |
| 3 grün (zweite) | $0371 | $0371 | 5,1 |
| 6 orange-braun (vorne) | $0842 | $0842 beim Wechsel, nach dem Blend in ~2 s auf **$0952** | 5,0 → 5,9 |
| 5 hell | $0c84 | $0c84 | 8,8 |
| 7 hellst | $0fdb | $0fdb | 13,4 |

- $0842 ist heute nicht heller als Grün. Darum der langsame Übergang nach dem Blend: Am Wechsel selbst bleibt jede Schicht in ihrer Farbe.
- Bandgrenzen nach dem Blend, Vorschlag: 600 / 1000 / 1400 / 1800 / 2500 / 3300. Ab 3300 kommen neue Sterne in $0003 kaum sichtbar herein und blenden über die Bänder ein.
- Optional `S3ZMAX` auf 3700 senken: Weiter hinten wird gar nicht gezeichnet (echtes unsichtbares Starten), und die Tabelle wird ~2,2 KB kleiner.

### Kosten (Schätzung) und Prüfung
- **Zyklen:**
  - Umwandlung: +70 Zyklen pro Stern (Skalierung je Schicht), ~5,6k in jedem der 4 Umwandlungs-Frames. Dort heute max 108,6k bei default, also Luft. Die anderen Seeds messe ich nach.
  - Förderband: ~40 Zyklen pro neuem Stern, höchstens 24 pro Frame, also < 1k.
  - Farbübergang: vernachlässigbar.
- **Speicher:** Code ~150 B, Daten 2–4 B. Mit `S3ZMAX` 3700 −2,2 KB.
- **Flugaufzeichnung:** unberührt.
- **Prüfung im Harness:** das neue Histogramm (`S3HIST`) für alle 6 Seeds.
  - Ziele: keine leeren Fächer im Feld ab +30 Frames, kleines Verhältnis zwischen vollstem und leerstem Fächer, Farbwechsel pro Frame ≤ ~6 (heute Schübe von 40+ in 100 Frames im selben Band);
  - dazu die Frame-Spitze ≤ 117k.
- **Risiken:**
  - Wie dunkel $0003 auf dem Monitor wirkt, zeigt nur WinUAE bzw. die echte Hardware.
  - Weil die Sterne über ihr Band gestreut sind, entsteht im ersten Blend-Abschnitt mehr Tiefenwirkung. Das ist gewollt, sollte aber angesehen werden.

---

**Nur in WinUAE zu beurteilen:**
- ob Sprite 4–7 mit `spr8` sauber laufen (Sprite-Test);
- wie Klappe, Zielen und Rückstoß wirken (B);
- wie die neuen Sternfarben auf dem Bildschirm wirken (C).

**Ich warte auf die Freigabe für B und C.**
