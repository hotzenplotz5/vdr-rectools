# AI Context

Dieses Dokument dient als Einstiegspunkt für KI-Systeme und neue Entwickler.

## Projektstatus

VDR-Rectools ist funktional weitgehend abgeschlossen.

Schwerpunkt:

- Stabilität
- Bugfixes
- Wartung

## Langfristige Rolle

Rectools dient als Media-Engine der zukünftigen VDR-Suite.

Folgende Funktionen sollen langfristig erhalten bleiben:

- rename_recording()
- move_recording()
- trash_recording()
- repair_recording()
- shrink_recording()
- cut_recording()
- check_recording()
- pes2ts_recording()

## Wichtige Regel

Keine Medienoperation direkt im Frontend.

Immer:

Frontend

↓

Queue

↓

Worker

↓

CLI

↓

functions.sh

## Nicht mehr stark ausbauen

Folgende Bereiche werden zukünftig in VDR-Suite entwickelt:

- SQLite
- REST API
- Metadatenbank
- Posterwall
- Plugin Registry
- Suchfunktion
- Modernes OSD
