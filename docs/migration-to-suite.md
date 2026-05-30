# Migration zu VDR-Suite

## Grundidee

Rectools bleibt die Media-Engine.

VDR-Suite wird die neue Plattform.

## Bleibt erhalten

- vdr-rectools-cli
- Queue-System
- Worker
- Aufnahmefunktionen

## Wird ersetzt

- aktuelles PHP-Webfrontend
- Dashboard
- Explorer

## Neue Komponenten

VDR-Suite wird enthalten:

- vdr-suite-core
- SQLite
- REST API
- Plugin Registry
- Medienbibliothek
- modernes OSD
- Webfrontend 2.0

## Übergangsstrategie

Kurzfristig:

Rectools-Webfrontend

↓

Rectools-CLI

Langfristig:

VDR-Suite-Web

↓

REST API

↓

Suite-Core

↓

Rectools-CLI

## Ziel

Nur eine zentrale Media-Engine.

Mehrere Frontends:

- OSD
- Web
- Mobile Apps
- externe Tools
