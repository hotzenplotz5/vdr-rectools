# VDR-Rectools Roadmap

## Projektstatus

VDR-Rectools ist funktional weitgehend abgeschlossen.

Der Schwerpunkt liegt künftig auf:

* Stabilität
* Wartbarkeit
* Bugfixes
* Paketpflege
* Dokumentation

Größere Neuentwicklungen erfolgen im Projekt **VDR-Suite**.

---

# Kurzfristige Ziele (3.x)

## Wartung

* Bugfixes
* Verbesserte Fehlermeldungen
* Optimierung der Debian-Paketierung
* Erweiterung der Dokumentation

## Webfrontend

* Kleinere Komfortverbesserungen
* UI-Verbesserungen
* Installationsvereinfachungen

## CLI

* Stabilisierung bestehender Funktionen
* Erweiterung von Logging und Diagnosefunktionen

---

# Mittelfristige Ziele (4.x)

## Modernisierung der Media-Engine

Prüfung einer schrittweisen Migration kritischer Komponenten von Bash nach C++:

* check_recording()
* repair_recording()
* shrink_recording()
* cut_recording()
* pes2ts_recording()

Ziel:

* höhere Geschwindigkeit
* bessere Wartbarkeit
* sauberere Fehlerbehandlung

Die bestehenden Bash-Funktionen bleiben Referenzimplementierung.

---

# VDR-Suite Integration

VDR-Rectools dient langfristig als zentrale Media-Engine.

Folgende Komponenten sollen weiterverwendet werden:

* Queue-System
* Worker-System
* CLI
* Aufnahmefunktionen

Insbesondere:

* rename_recording()
* move_recording()
* trash_recording()
* repair_recording()
* shrink_recording()
* cut_recording()
* check_recording()
* pes2ts_recording()

---

# Funktionen, die nicht mehr in Rectools entwickelt werden

Folgende Bereiche werden ausschließlich in VDR-Suite umgesetzt:

* SQLite-Datenbank
* REST API
* Metadatenverwaltung
* TVScraper Integration
* Plugin Registry
* Globale Suche
* Posterwall
* Serienbibliothek
* Modernes OSD
* Mobile Clients

---

# Langfristige Vision

Architektur:

Frontend

↓

REST API

↓

VDR-Suite Core

↓

VDR-Rectools CLI

↓

Media Engine

↓

FFmpeg / VDR

Dadurch können mehrere Oberflächen dieselbe Media-Engine verwenden:

* VDR OSD
* Webfrontend
* Mobile Apps
* Externe Werkzeuge

---

# Projektphilosophie

Code erklärt das Wie.

Dokumentation erklärt das Warum.

VDR-Rectools soll eine stabile und zuverlässige Grundlage für die zukünftige VDR-Suite bilden.
