PhoneCam Receiver – Anleitung
==============================

EINMALIGE EINRICHTUNG
----------------------
1. OBS Studio installieren (kostenlos): https://obsproject.com
   (Version 28 oder neuer – das ist seit einigen Jahren Standard.)

2. OBS einmal öffnen.
   - Unten rechts auf "Virtuelle Kamera starten" klicken.
   - Direkt danach wieder auf "Virtuelle Kamera beenden" klicken.
   - Das war's – dieser Schritt registriert den Kameratreiber im
     System. OBS muss danach NICHT mehr geöffnet sein.

3. OBS schließen. Ab jetzt brauchst du OBS nicht mehr zu öffnen.

JEDES MAL BEIM BENUTZEN
------------------------
1. PhoneCam-App auf dem iPhone öffnen (im selben WLAN wie der PC).
   Die App zeigt eine IP-Adresse und einen Port an, z.B.
   192.168.1.42 : 5050

2. PhoneCamReceiver.exe auf dem PC starten.

3. Die IP-Adresse vom iPhone in das Feld "iPhone IP-Adresse" eintragen,
   Port prüfen (Standard: 5050).

4. Auf "Verbinden" klicken.

5. Häkchen bei "Als Webcam bereitstellen" setzen (ist standardmäßig an).

6. In Zoom, Discord, Browser-Videocall etc. als Kamera
   "OBS Virtual Camera" auswählen – das ist jetzt dein iPhone.

HÄUFIGE PROBLEME
-----------------
- "OBS Virtual Camera nicht verfügbar": Schritt 2 der einmaligen
  Einrichtung wiederholen (OBS öffnen, Virtuelle Kamera kurz starten
  und wieder stoppen, dann OBS schließen).

- Kein Bild: Prüfen, ob iPhone und PC im SELBEN WLAN sind (nicht
  Gast-WLAN, kein mobiles Datennetz auf dem iPhone). Manche Router-
  /Firewall-Einstellungen blockieren Geräte-zu-Geräte-Verbindungen
  ("AP-Isolation") – ggf. in den Router-Einstellungen deaktivieren.

- Ruckler/Verzögerung: FPS oder Auflösung in der iPhone-App-Einstellung
  reduzieren (z.B. 720p/30fps statt 1080p/60fps).
