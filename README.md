# PhoneCam – iPhone als PC-Webcam

Eigenes "iPhone als Webcam"-System (wie iVCam/EpocCam), bestehend aus:
- **iOS-App** (Swift/SwiftUI): zeigt Kamerabild, Zoom, Front/Back-Switch,
  Foto-aus-Galerie, FPS/Qualitäts-Einstellungen, streamt per WLAN.
- **Windows-Programm** (C#/WPF): empfängt den Stream, zeigt Vorschau,
  stellt das Bild als echte virtuelle Webcam bereit (via OBS Virtual
  Camera-Treiber, ohne dass OBS selbst laufen muss).

## Schritt 1: iOS-App als IPA bauen (über GitHub Actions, kein Mac nötig)

1. Dieses gesamte Projekt in ein eigenes GitHub-Repository hochladen
   (z.B. über die GitHub-Webseite: "Add file" → "Upload files", den
   kompletten Ordnerinhalt hochladen, oder per `git push`).

2. Im Repository auf **Actions** klicken.

3. Workflow **"Build PhoneCam IPA"** auswählen → **"Run workflow"**
   klicken → kurz warten (ca. 5–10 Minuten).

4. Nach Abschluss: unten bei "Artifacts" auf **PhoneCam-IPA** klicken,
   die Datei `PhoneCam.ipa` wird heruntergeladen (als .zip, darin liegt
   die .ipa).

5. Mit **Sideloadly** wie gewohnt auf dein iPhone installieren
   (Apple-ID eingeben, IPA auswählen, Sideloadly signiert sie dabei
   automatisch – das ist normal und nötig).

   Wichtig: Ohne kostenpflichtigen Apple Developer Account hält die
   Signatur nur 7 Tage, danach muss in Sideloadly neu signiert werden
   (kein erneuter Build nötig, nur "Resign"/erneutes Installieren).

## Schritt 2: Windows-Programm bauen

1. Workflow **"Build PhoneCam Receiver (Windows)"** in den Actions
   ausführen (Run workflow).

2. Nach Abschluss: Artifact **PhoneCamReceiver-Windows** herunterladen.
   Enthält:
   - `PhoneCamReceiver.exe` – das Hauptprogramm
   - `vcam_bridge.exe` – interner Helfer für die virtuelle Kamera
     (muss im selben Ordner liegen bleiben)
   - `LIES-MICH.txt` – Anleitung

3. OBS Studio (kostenlos, https://obsproject.com) installieren, einmal
   öffnen, "Virtuelle Kamera starten" klicken, dann wieder stoppen,
   OBS schließen. (Details in LIES-MICH.txt)

## Schritt 3: Benutzen

1. iPhone-App öffnen (gleiches WLAN wie der PC).
2. Angezeigte IP-Adresse + Port in PhoneCamReceiver.exe eintragen.
3. "Verbinden" klicken.
4. In Zoom/Discord/Browser als Kamera "OBS Virtual Camera" wählen.

## Projektstruktur

```
PhoneCam/
├── ios/PhoneCam/              iOS-App (Swift/SwiftUI)
│   ├── project.yml            XcodeGen-Konfiguration
│   └── Sources/PhoneCam/      Quellcode
├── windows/
│   ├── PhoneCamReceiver/      Windows-App (C#/WPF)
│   ├── vcam_bridge/           Python-Helfer für virtuelle Kamera
│   └── README-WINDOWS.txt     Anleitung für PC-Seite
└── .github/workflows/         Automatische Build-Skripte
```
