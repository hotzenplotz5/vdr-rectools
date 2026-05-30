# Architektur

## Ziel

VDR-Rectools stellt Werkzeuge zur Verwaltung und Bearbeitung von VDR-Aufnahmen bereit.

## Komponenten

### CLI

vdr-rectools-cli

Enthält:

- vdr-rectools
- vdr-rectools-worker
- functions.sh
- media_tools.sh
- Queue-System

### Webfrontend

vdr-rectools-web

Enthält:

- Dashboard
- Explorer
- Einstellungen
- Log Viewer

## Ausführungsmodell

Frontend

↓

Queue

↓

Worker

↓

CLI

↓

functions.sh

↓

FFmpeg / VDR

## Designprinzip

Das Frontend führt niemals direkt Medienoperationen aus.

Alle Aktionen laufen über die Queue und den Worker.
