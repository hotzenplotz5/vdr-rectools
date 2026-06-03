# CLI Exit-Code Audit

## Ziel

Dieses Dokument beschreibt das aktuelle Rueckgabeverhalten der CLI-Kommandos von `vdr-rectools`.

Es ist eine reine Analyse- und Dokumentationsphase. Es enthaelt noch keine Code-Aenderung.

Der Zweck ist, vor spaeteren Korrekturen nachzuweisen, welche Kommandos fuer VDR-Suite bereits stabil genug sind und welche Kommandos Rueckgabewerte verlieren koennen.

## Relevante Dateien

Analysiert wurden:

- `usr/bin/vdr-rectools`
- `usr/bin/vdr-rectools-worker`
- `usr/share/vdr-rectools/functions.sh`

## Grundproblem

`usr/bin/vdr-rectools` endet nach dem `case`-Block mit einem pauschalen:

```bash
exit 0
```

Kommandos, die innerhalb ihres Case-Zweigs keinen eigenen `exit` ausfuehren, geben dadurch am Ende immer Erfolg zurueck, sofern der letzte Shell-Befehl nicht vorher explizit beendet.

Bei mehreren Einzelaktionen wird nach der eigentlichen Aktion zusaetzlich noch ausgefuehrt:

```bash
/usr/bin/svdrpsend UPDT >/dev/null 2>&1 || true
```

Dadurch kann der Rueckgabewert der eigentlichen Aktion ueberschrieben oder verdeckt werden.

Fuer VDR-Suite ist das kritisch, weil VDR-Suite spaeter sicher unterscheiden muss zwischen:

- erfolgreich abgeschlossen
- fehlgeschlagen
- falsche Parameter
- ungueltige Aufnahme
- externer Befehl fehlgeschlagen
- Aktion abgebrochen

## Aktuelles Verhalten nach Kommando

| Kommando | Aktuelle Aktion | Aktueller Exit-Code aus CLI-Sicht | Risiko fuer VDR-Suite |
|---|---|---:|---|
| `start` | prueft `is_running`, dann `run_scan normal` | bei bereits laufendem Prozess `1`, sonst wahrscheinlich `0` | Fehler aus `run_scan` werden nicht explizit propagiert |
| `import` | prueft `is_running`, dann `run_scan import` | bei bereits laufendem Prozess `1`, sonst wahrscheinlich `0` | Fehler aus `run_scan` werden nicht explizit propagiert |
| `repair` | prueft `is_running`, dann `run_scan repair` | bei bereits laufendem Prozess `1`, sonst wahrscheinlich `0` | Fehler einzelner Aufnahmen werden nicht als CLI-Fehler sichtbar |
| `pes2ts` ohne Pfad | prueft `is_running`, dann `run_scan pes2ts` | bei bereits laufendem Prozess `1`, sonst wahrscheinlich `0` | Fehler einzelner Konvertierungen koennen nur im Log sichtbar sein |
| `pes2ts` mit Pfad | ruft `convert_pes2ts <Pfad>`, danach `svdrpsend ... || true` | wahrscheinlich immer `0` nach Skriptende | kritisch: Fehler aus `convert_pes2ts` koennen verloren gehen |
| `pes2ts_single` | ruft `convert_pes2ts <Pfad>`, danach `svdrpsend ... || true` | wahrscheinlich immer `0` nach Skriptende | kritisch |
| `rename_single` | ruft `rename_recording <Pfad> <Name>`, danach `svdrpsend ... || true` | wahrscheinlich immer `0` nach Skriptende | kritisch |
| `move_single` | ruft `move_recording <Pfad> <Ziel>`, danach `svdrpsend ... || true` | wahrscheinlich immer `0` nach Skriptende | kritisch |
| `trash_single` | ruft `trash_recording <Pfad>`, danach `svdrpsend ... || true` | wahrscheinlich immer `0` nach Skriptende | kritisch |
| `repair_single` | ruft `process_folder <Pfad> repair`, danach `chown` und `svdrpsend ... || true` | wahrscheinlich immer `0` nach Skriptende | kritisch |
| `check_single` | ruft `process_folder <Pfad> check` | unklar; ohne explizites `exit` faellt es ebenfalls zum globalen `exit 0` durch | kritisch, weil Check fuer VDR-Suite besonders wichtig ist |
| `sync_single` | ruft `process_folder <Pfad> normal`, danach `chown` und `svdrpsend ... || true` | wahrscheinlich immer `0` nach Skriptende | kritisch |
| `shrink_single` | ruft `process_folder <Pfad> shrink`, danach `chown` und `svdrpsend ... || true` | wahrscheinlich immer `0` nach Skriptende | kritisch |
| `cut_single` | ruft `process_folder <Pfad> cut`, danach `chown` und `svdrpsend ... || true` | wahrscheinlich immer `0` nach Skriptende | kritisch |
| `cron` | prueft `AUTO_START_NIGHT`, optional `is_running`, dann `run_scan normal` | bei bereits laufendem Prozess `1`, sonst wahrscheinlich `0` | fuer VDR-Suite weniger relevant |
| `status` | interaktiver Status | beendet nach Abbruch wahrscheinlich `0` | fuer VDR-Suite nicht als maschinenlesbare Schnittstelle geeignet |
| `osd-status` | ruft `show_osd_status` | wahrscheinlich `0` | Legacy/Diagnose |
| `refresh` | ruft `export_html_status` | wahrscheinlich `0` | Legacy |
| `update-html` | ruft `export_html_status` | wahrscheinlich `0` | Legacy |
| `osd-confirm` | ruft `handle_osd_confirm` | unklar, faellt ohne explizites `exit` zum globalen `exit 0` durch | Legacy/OSD |
| `diag` | ruft `show_diagnostics`, dann `exit 0` | `0` | ok |
| `stop` | beendet Prozesse und raeumt Statusdateien auf | wahrscheinlich `0` | ok als Bedienkommando, aber nicht streng validiert |
| `check_running` | gibt bei laufendem Prozess `TRY_AGAIN=15` aus und `exit 1`, sonst `exit 0` | stabil | ok fuer Shutdown-Hook |
| `help`, `--help`, `-h` | Hilfe anzeigen, dann `exit 0` | stabil | ok |
| unbekannter Befehl | Fehlerausgabe, Hilfe, dann `exit 1` | stabil | ok |

## Worker-Auswirkung

`usr/bin/vdr-rectools-worker` wertet nach jedem CLI-Aufruf den Rueckgabewert aus:

```bash
SUCCESS=$?
```

Danach schreibt der Worker anhand dieses Wertes entweder:

```text
state=done
```

oder:

```text
state=error
```

Wenn die CLI trotz fehlgeschlagener Aktion `0` zurueckgibt, markiert der Worker den Job faelschlich als erfolgreich.

Das betrifft besonders:

- `repair`
- `cut`
- `check`
- `rename`
- `move`
- `trash`
- `shrink`
- `pes2ts` mit Pfadparameter

## Bewertung fuer VDR-Suite

Die CLI ist noch nicht stabil genug als maschinenlesbare Backend-Schnittstelle.

Fuer eine spaetere VDR-Suite-Anbindung muessen mindestens die Einzelkommandos echte Rueckgabewerte liefern:

- `check_single`
- `repair_single`
- `cut_single`
- `shrink_single`
- `pes2ts_single`
- `rename_single`
- `move_single`
- `trash_single`

Globale Scan-Kommandos koennen weiterhin eine andere Semantik haben, muessen aber dokumentieren, ob Fehler einzelner Aufnahmen den Gesamtlauf fehlschlagen lassen oder nur im Log erscheinen.

## Naechster Schritt

Punkt 2 sollte das aktuelle Verhalten lokal mit einfachen Negativtests nachweisen.

Beispiele:

```bash
vdr-rectools check_single /pfad/der/nicht/existiert
echo $?

vdr-rectools repair_single /pfad/der/nicht/existiert
echo $?

vdr-rectools pes2ts_single /pfad/der/nicht/existiert
echo $?

vdr-rectools move_single /pfad/der/nicht/existiert Ziel
echo $?

vdr-rectools rename_single /pfad/der/nicht/existiert NeuerName
echo $?

vdr-rectools trash_single /pfad/der/nicht/existiert
echo $?
```

Erwartung fuer die aktuelle Version:

- Viele dieser Kommandos werden vermutlich `0` liefern, obwohl die Aktion nicht erfolgreich war.
- Das muss vor einer VDR-Suite-Anbindung korrigiert werden.

## Keine Aenderung in dieser Phase

Diese Phase dokumentiert nur das Ist-Verhalten.

Code-Korrekturen gehoeren in eine eigene kleine Folgeaenderung.
