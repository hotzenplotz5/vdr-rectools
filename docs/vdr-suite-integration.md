# VDR-Suite Integration

## Ziel

VDR-Rectools bleibt ein stabiles CLI-/Worker-Werkzeug fuer bestehende und zukuenftige VDR-Aufnahmeaktionen.

VDR-Suite uebernimmt spaeter die moderne Oberflaeche, API, Statusdarstellung, Jobverwaltung und Benutzerfuehrung.

Das Webfrontend von VDR-Rectools wird nicht weiterentwickelt. Es bleibt nur fuer Legacy-Kompatibilitaet erhalten. Aenderungen am Webfrontend erfolgen nur noch als Bugfixes, wenn bestehende Funktionen kaputt sind.

## Grundentscheidung

VDR-Rectools wird nicht vollstaendig nach C++ portiert.

Stattdessen bleibt Rectools zunaechst ein stabiles Bash-basiertes Backend-Werkzeug. Einzelne sicherheitskritische oder fuer VDR-Suite besonders wichtige Kernfunktionen koennen spaeter gezielt nach C++ ausgelagert werden.

## Wichtiger Architekturgrundsatz

Native VDR-Funktionen sollen in VDR-Suite bevorzugt ueber das VDR-RESTfulAPI-Plugin angebunden werden.

VDR-Rectools soll nicht als Ersatz fuer native VDR-Funktionen verwendet werden, wenn RESTfulAPI diese Funktion bereits sauber bereitstellt.

Damit gilt fuer VDR-Suite langfristig:

```text
RESTfulAPI = VDR-Fachlogik
Rectools   = Datei-, Import-, Reparatur- und Workflow-Engine
VDR-Suite  = Orchestrierung, API, moderne Oberflaeche und Rechte-/Statusmodell
```

Diese Trennung verhindert Doppelimplementierungen und haelt VDR-Suite VDR-zentriert.

## Wichtiger Projektstatus: VDR-Suite zuerst lauffaehig machen

Die langfristige Frage, ob einzelne Rectools-Funktionen spaeter direkt in VDR-Suite uebernommen werden, darf die aktuelle Entwicklung nicht blockieren.

Die Prioritaet bleibt:

```text
1. VDR-Suite lauffaehig machen
2. RESTfulAPI sauber anbinden
3. Rectools als stabiles externes Werkzeug nutzbar halten
4. Erst danach ueber native Uebernahme einzelner Funktionen entscheiden
```

Zum aktuellen Zeitpunkt wird kein Paketkonflikt zwischen VDR-Suite und VDR-Rectools eingefuehrt.

Ein spaeteres Paketmodell mit `Conflicts`, `Replaces` oder einer Migration von Rectools-Funktionen nach VDR-Suite darf erst geplant werden, wenn VDR-Suite funktional gleichwertige Ersatzfunktionen bereitstellt und diese mit echten Aufnahmen getestet wurden.

## RESTfulAPI bevorzugen fuer native VDR-Funktionen

RESTfulAPI soll spaeter bevorzugt genutzt werden fuer:

- Aufnahmen auflisten
- Aufnahme loeschen
- Aufnahme verschieben
- Aufnahme umbenennen, sofern sauber ueber Move abbildbar
- Schnitt starten
- Schnittmarken lesen, schreiben und loeschen
- Timer
- EPG
- Kanaele
- VDR-Status
- Live-VDR-Interaktion

Diese Funktionen gehoeren fachlich zum VDR-Kern und sollten nicht erneut in Rectools oder VDR-Suite nachgebaut werden.

## Einfluss einer nativen VDR-PES-zu-TS-Migration

Die langfristige Rolle der PES-zu-TS-Konvertierung in VDR-Rectools haengt von der weiteren Entwicklung des VDR-Kerns ab.

Wenn VDR kuenftig eine native PES-zu-TS-Migration bereitstellt, soll diese Funktion fuer VDR-Suite bevorzugt ueber VDR selbst genutzt werden.

In diesem Fall dient die Rectools-Implementierung von PES-zu-TS primaer:

- der Abwaertskompatibilitaet
- bestehenden Installationen
- aelteren VDR-Versionen
- Fallback-Szenarien

Fuer VDR-Suite ist keine dauerhafte eigene PES-zu-TS-Neuimplementierung vorgesehen, sofern eine native VDR-Loesung verfuegbar ist.

Langfristige Prioritaet:

```text
1. Native VDR-Funktion
2. RESTfulAPI-Anbindung an die native VDR-Funktion
3. Rectools-Fallback fuer aeltere Systeme
```

## Fuer VDR-Suite wertvolle Rectools-Funktionen

Langfristig relevante Rectools-CLI-Funktionen:

- import
- check_single
- repair_single
- shrink_single
- pes2ts
- pes2ts_single

Diese Funktionen bieten Mehrwert, der ueber native VDR-RESTfulAPI-Funktionen hinausgeht.

Sollte PES-zu-TS in VDR selbst verfuegbar werden, verschiebt sich `pes2ts` in Richtung Legacy-/Fallback-Funktion.

## Rectools-Funktionen mit Legacy- oder Fallback-Charakter

Folgende Rectools-Kommandos bleiben fuer Kompatibilitaet und Notfall-/Fallback-Szenarien erhalten, sollen aber fuer VDR-Suite nicht die primaere Schnittstelle sein, wenn RESTfulAPI verfuegbar ist:

- cut_single
- move_single
- rename_single
- trash_single

Diese Kommandos muessen trotzdem stabile Exit-Codes liefern, weil sie im Worker, in bestehenden Installationen oder als Fallback genutzt werden koennen.

## Langfristige Perspektive von Rectools

Nach aktueller Analyse werden zahlreiche klassische Recording-Funktionen bereits durch VDR und RESTfulAPI bereitgestellt:

- Delete
- Move
- Rename, sofern sauber ueber Move abbildbar
- Cut
- Marks

Sollte zusaetzlich PES-zu-TS in den VDR-Kern wandern, verbleiben in Rectools hauptsaechlich:

- Import
- Check
- Repair
- Shrink/Reencode
- Worker- und Batch-Verarbeitung

Diese Funktionen koennen langfristig entweder als eigenstaendiges Backend bestehen bleiben oder schrittweise in VDR-Suite uebernommen werden.

Zum aktuellen Zeitpunkt ist keine Entscheidung ueber eine Abloesung von Rectools getroffen.

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

- Import vorhandener Videodateien in VDR-Aufnahmen
- Pruefung und Reparatur von Aufnahmen
- PES-zu-TS-Konvertierung als Uebergang oder Fallback, solange keine native VDR-Loesung genutzt wird
- Schrumpfen und Reencode-Workflows
- lang laufende Worker-Jobs
- Batch-Verarbeitung
- klassische Logdateien
- Fallback-Kommandos fuer einzelne Dateioperationen

### RESTfulAPI

RESTfulAPI ist bevorzugt zustaendig fuer native VDR-Funktionen:

- Recording-Liste
- Recording-Details
- Recording-Delete
- Recording-Move
- Recording-Cut
- Recording-Marks
- Timer
- EPG
- Channels
- Status

### VDR-Suite

VDR-Suite uebernimmt spaeter:

- moderne Oberflaeche
- eigene REST-API
- Jobmodell
- Fortschrittsanzeige
- Statusauswertung
- Benutzerfuehrung
- Fehlerdarstellung
- Rechte- und Sicherheitsmodell
- Orchestrierung von RESTfulAPI und Rectools
- maschinenlesbare Auswertung von Rectools-Aktionen

## Langfristig stabile CLI-Kommandos

Die folgenden Rectools-Kommandos sollen langfristig stabil bleiben:

```text
vdr-rectools import
vdr-rectools check_single <recording-path>
vdr-rectools repair_single <recording-path>
vdr-rectools shrink_single <recording-path>
vdr-rectools pes2ts
vdr-rectools pes2ts_single <recording-path>
```

Die folgenden Kommandos bleiben als Legacy-/Fallback-Kommandos erhalten:

```text
vdr-rectools cut_single <recording-path>
vdr-rectools move_single <recording-path> <target-relative-dir>
vdr-rectools rename_single <recording-path> <new-title>
vdr-rectools trash_single <recording-path>
```

## Wichtiger aktueller Befund: Exit-Codes

Die CLI-Kommandos fuer Einzelaktionen muessen fuer VDR-Suite, Worker und bestehende Automatisierungen verlaessliche Exit-Codes liefern.

Bei der Analyse wurde festgestellt, dass mehrere Einzelkommandos die Rueckgabewerte der eigentlichen Aktion nicht stabil an den aufrufenden Prozess weiterreichten. Besonders relevant waren:

- pes2ts mit Pfadparameter
- pes2ts_single
- rename_single
- move_single
- trash_single
- repair_single
- sync_single
- shrink_single
- cut_single

Der Grund war, dass nach der eigentlichen Aktion teilweise noch `svdrpsend ... || true` ausgefuehrt wurde und das Skript anschliessend am Dateiende mit `exit 0` beendet wurde. Dadurch konnten Fehler fuer externe Aufrufer unsichtbar werden.

Dieser Punkt wurde fuer die Einzelkommandos korrigiert. Die Kommandos reichen den Rueckgabewert der eigentlichen Aktion nun wieder an den aufrufenden Prozess weiter.

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
- shrink/reencode
- import

PES-zu-TS soll nicht dauerhaft in VDR-Suite nachgebaut werden, wenn VDR selbst diese Migration bereitstellt.

Move, Rename, Delete und Cut sollen fuer VDR-Suite primaer ueber RESTfulAPI genutzt werden, sofern das jeweilige Zielsystem RESTfulAPI bereitstellt und die Funktion dort korrekt arbeitet.

Die Bash-Skripte koennen dabei als Steuerhuelle erhalten bleiben.

## Nicht-Ziele

Nicht geplant sind:

- neues Webfrontend
- Ausbau des PHP-Explorers
- neue UI-Funktionen in Rectools
- grosse Architekturumbauten
- vollstaendige C++-Portierung
- Nachbau nativer VDR-Funktionen, die RESTfulAPI bereits bereitstellt
- dauerhafte eigene PES-zu-TS-Neuimplementierung in VDR-Suite, falls VDR diese Funktion nativ bereitstellt
- Paketkonflikt zwischen VDR-Suite und VDR-Rectools, bevor VDR-Suite funktional gleichwertige Ersatzfunktionen besitzt
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
- RESTfulAPI-vs-Rectools-Zustaendigkeit dokumentieren

### Phase C: Exit-Codes und Logs vereinheitlichen

- Rueckgabewerte pruefen
- problematische Stellen nachweisen
- Exit-Code-Modell schrittweise umsetzen
- Logverhalten dokumentieren

### Phase D: VDR-Suite-Anbindung vorbereiten

- VDR-Suite zuerst lauffaehig machen
- RESTfulAPI bevorzugt fuer native VDR-Funktionen einplanen
- RectoolsAdapter nur fuer Import, Check, Repair, PES2TS, Shrink und Worker-Jobs einplanen
- PES2TS langfristig als VDR-native Funktion bevorzugen, falls verfuegbar
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
- native VDR-Funktionen nicht doppelt bauen, wenn RESTfulAPI sie bereits bereitstellt
- keine Paketkonflikte einfuehren, bevor VDR-Suite lauffaehig ist und funktional gleichwertige Ersatzfunktionen besitzt
