# VDR-Suite Integration

## Ziel

VDR-Rectools bleibt ein stabiles CLI-/Worker-Werkzeug fuer bestehende und zukuenftige VDR-Aufnahmeaktionen.

VDR-Suite uebernimmt spaeter die moderne Oberflaeche, API, Statusdarstellung, Jobverwaltung und Benutzerfuehrung.

Das Webfrontend von VDR-Rectools wird nicht weiterentwickelt. Es bleibt nur fuer Legacy-Kompatibilitaet erhalten. Aenderungen am Webfrontend erfolgen nur noch als Bugfixes, wenn bestehende Funktionen kaputt sind.

## Grundentscheidung

VDR-Rectools wird nicht vollstaendig nach C++ portiert.

Stattdessen bleibt Rectools zunaechst ein stabiles Bash-basiertes Backend-Werkzeug. Einzelne sicherheitskritische oder fuer VDR-Suite besonders wichtige Kernfunktionen koennen spaeter gezielt nach C++ ausgelagert werden.

## Fuer VDR-Suite wertvolle Funktionen

Langfristig relevante CLI-Funktionen:

- import
- check_single
- repair_single
- cut_single
- shrink_single
- pes2ts
- pes2ts_single
- move_single
- rename_single
- trash_single

Diese Funktionen sollen als stabile Backend-Schnittstelle betrachtet werden.

## Legacy-Funktionen

Folgende Bereiche bleiben nur aus Kompatibilitaetsgruenden erhalten:

- Webfrontend
- PHP-Explorer
- HTML-Dashboard
- update-html
- refresh
- browserbasierte Bedienlogik

Diese Bereiche sollen nicht weiter ausgebaut werden.

## Zustaendigkeiten

### VDR-Rectools

VDR-Rectools bleibt zustaendig fuer:

- konkrete Dateioperationen auf VDR-Aufnahmen
- Import vorhandener Aufnahmen
- Pruefung und Reparatur von Aufnahmen
- PES-zu-TS-Konvertierung
- Schneiden und Schrumpfen
- Verschieben, Umbenennen und Papierkorb-Aktionen
- einfache Worker-Verarbeitung
- klassische Logdateien

### VDR-Suite

VDR-Suite uebernimmt spaeter:

- moderne Oberflaeche
- REST-API
- Jobmodell
- Fortschrittsanzeige
- Statusauswertung
- Benutzerfuehrung
- Fehlerdarstellung
- Rechte- und Sicherheitsmodell
- maschinenlesbare Auswertung von Rectools-Aktionen

## Langfristig stabile CLI-Kommandos

Die folgenden Kommandos sollen langfristig stabil bleiben:

```text
vdr-rectools import
vdr-rectools check_single <recording-path>
vdr-rectools repair_single <recording-path>
vdr-rectools cut_single <recording-path>
vdr-rectools shrink_single <recording-path>
vdr-rectools pes2ts
vdr-rectools pes2ts_single <recording-path>
vdr-rectools move_single <recording-path> <target-relative-dir>
vdr-rectools rename_single <recording-path> <new-title>
vdr-rectools trash_single <recording-path>
```

## Wichtiger aktueller Befund: Exit-Codes

Die CLI-Kommandos fuer Einzelaktionen muessen fuer VDR-Suite verlaessliche Exit-Codes liefern.

Bei der aktuellen Analyse wurde festgestellt, dass mehrere Einzelkommandos die Rueckgabewerte der eigentlichen Aktion nicht stabil an den aufrufenden Prozess weiterreichen. Besonders relevant sind:

- pes2ts mit Pfadparameter
- pes2ts_single
- rename_single
- move_single
- trash_single
- repair_single
- sync_single
- shrink_single
- cut_single

Der Grund ist, dass nach der eigentlichen Aktion teilweise noch `svdrpsend ... || true` ausgefuehrt wird und das Skript anschliessend am Dateiende mit `exit 0` beendet wird. Dadurch koennen Fehler fuer externe Aufrufer unsichtbar werden.

Dieser Punkt muss vor einer sauberen VDR-Suite-Anbindung korrigiert und getestet werden.

## Zielmodell fuer Exit-Codes

```text
0 = Erfolg
1 = allgemeiner Fehler
2 = falsche Parameter
3 = Datei oder Ordner nicht gefunden
4 = ungueltige VDR-Aufnahme oder ungueltiges Format
5 = externer Befehl fehlgeschlagen
6 = Aktion abgebrochen oder nicht ausfuehrbar
```

Bestehende Funktionen duerfen erst geaendert werden, nachdem ihr aktuelles Verhalten nachgewiesen und getestet wurde.

## Logging

Bestehende Logdateien bleiben vorerst massgeblich:

```text
/var/log/vdr-rectools.log
/var/log/vdr-rectools-worker.log
```

VDR-Suite kann diese Logs spaeter anzeigen oder auswerten.

Eine spaetere strukturierte Ausgabe ist moeglich, aber nicht Voraussetzung fuer die naechste Entwicklungsphase.

## Optionale JSON-Ausgabe

Eine optionale JSON-Ausgabe kann spaeter geprueft werden.

Beispiel fuer eine moegliche spaetere Form:

```bash
vdr-rectools check_single --json <recording-path>
```

JSON-Ausgabe ist kein kurzfristiges Ziel.

Prioritaet hat zuerst eine stabile und dokumentierte CLI-Schnittstelle.

## Moegliche spaetere C++-Auslagerung

Eine vollstaendige C++-Portierung von VDR-Rectools ist nicht geplant.

C++ kann spaeter fuer einzelne Kernfunktionen sinnvoll sein, insbesondere fuer:

- check_single
- repair_single
- pes2ts_single
- move_single
- rename_single
- trash_single

Die Bash-Skripte koennen dabei als Steuerhuelle erhalten bleiben.

## Nicht-Ziele

Nicht geplant sind:

- neues Webfrontend
- Ausbau des PHP-Explorers
- neue UI-Funktionen in Rectools
- grosse Architekturumbauten
- vollstaendige C++-Portierung
- HTML als zukuenftige Schnittstelle fuer VDR-Suite

## Roadmap

### Phase A: CLI stabilisieren

- bestehende Kommandos inventarisieren
- Parameter pruefen
- aktuelles Verhalten dokumentieren
- gefaehrliche Dateioperationen testen
- Exit-Code-Verlust bei Einzelkommandos korrigieren

### Phase B: CLI-Schnittstelle dokumentieren

- stabile Kommandos festlegen
- Beispiele ergaenzen
- Seiteneffekte beschreiben
- Legacy-Kommandos kennzeichnen

### Phase C: Exit-Codes und Logs vereinheitlichen

- Rueckgabewerte pruefen
- problematische Stellen nachweisen
- Exit-Code-Modell schrittweise umsetzen
- Logverhalten dokumentieren

### Phase D: VDR-Suite-Anbindung vorbereiten

- maschinenlesbare Ausgabe pruefen
- JSON optional planen
- keine bestehende CLI brechen

### Phase E: Webfrontend einfrieren

- keine neuen Features
- nur Bugfixes
- keine Explorer-Erweiterungen
- keine neue Browserlogik

## Tests vor Aenderungen

Vor jeder Aenderung mindestens:

```bash
bash -n usr/bin/vdr-rectools
bash -n usr/bin/vdr-rectools-worker
bash -n usr/share/vdr-rectools/functions.sh
```

Wenn verfuegbar zusaetzlich:

```bash
shellcheck usr/bin/vdr-rectools usr/bin/vdr-rectools-worker usr/share/vdr-rectools/functions.sh
```

Nach funktionalen Aenderungen muessen echte Tests mit Testaufnahmen erfolgen.

## Entwicklungsregeln

- Ursache zuerst nachweisen
- keine Schnellschuesse
- keine Webfrontend-Erweiterung
- nur Bugfixes am Webfrontend
- keine grosse C++-Portierung ohne konkreten Nutzen
- nach jeder Aenderung testen
- Aenderungen klein halten
- CLI-Verhalten nicht unbeabsichtigt brechen
