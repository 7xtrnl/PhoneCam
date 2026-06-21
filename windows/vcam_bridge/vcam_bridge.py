"""
vcam_bridge.py
--------------
Kleiner Hintergrund-Helfer, der von PhoneCamReceiver.exe automatisch
gestartet wird (unsichtbar, kein Fenster). Er bekommt über stdin
fortlaufend rohe BGR24-Frames fester Größe geliefert und reicht sie
über die bewährte, offizielle pyvirtualcam-Bibliothek an den
OBS-Virtual-Camera-Treiber weiter.

WICHTIG: Dieses Skript wird NICHT von Hand ausgeführt. Es wird beim
Build in eine eigenständige vcam_bridge.exe verpackt (siehe
build_bridge.yml GitHub Action) und von der C#-App im Hintergrund
gestartet. Der Nutzer sieht nie ein Python-Fenster oder eine Konsole.

Protokoll auf stdin (vom C#-Programm geschrieben):
  1) Eine Zeile mit "WIDTH HEIGHT FPS\n" (ASCII, z.B. "1280 720 30\n")
  2) Danach fortlaufend: jeweils genau WIDTH*HEIGHT*3 Bytes pro Frame
     im BGR24-Format (passend zu System.Drawing.Bitmap-Pixeldaten).

Bei Fehlern oder wenn OBS Virtual Camera nicht installiert ist, schreibt
das Skript eine Fehlermeldung nach stderr und beendet sich; die C#-App
fängt das ab und zeigt dem Nutzer eine verständliche Meldung.
"""

import sys
import numpy as np

def main():
    raw_header = sys.stdin.buffer.readline()
    if not raw_header:
        sys.stderr.write("Keine Header-Zeile empfangen, beende.\n")
        sys.exit(1)

    try:
        parts = raw_header.decode("ascii").strip().split()
        width, height, fps = int(parts[0]), int(parts[1]), int(parts[2])
    except Exception as e:
        sys.stderr.write(f"Ungueltiger Header: {raw_header!r} ({e})\n")
        sys.exit(1)

    frame_size = width * height * 3  # BGR24

    try:
        import pyvirtualcam
    except ImportError:
        sys.stderr.write(
            "PYVIRTUALCAM_MISSING: Die pyvirtualcam-Bibliothek fehlt im "
            "gebuendelten Python. Build-Problem, bitte erneut bauen.\n"
        )
        sys.exit(2)

    try:
        cam = pyvirtualcam.Camera(
            width=width,
            height=height,
            fps=fps,
            fmt=pyvirtualcam.PixelFormat.BGR,
            device="OBS Virtual Camera",
        )
    except RuntimeError as e:
        # Das ist der Fall, wenn OBS (>=28) nicht installiert ist oder
        # die virtuelle Kamera noch nie gestartet wurde.
        sys.stderr.write(f"OBS_VCAM_NOT_AVAILABLE: {e}\n")
        sys.exit(3)

    sys.stderr.write(f"READY {cam.device}\n")
    sys.stderr.flush()

    stdin = sys.stdin.buffer
    try:
        while True:
            data = stdin.read(frame_size)
            if not data or len(data) < frame_size:
                break  # C#-Seite hat die Pipe geschlossen
            frame = np.frombuffer(data, dtype=np.uint8).reshape((height, width, 3))
            cam.send(frame)
            cam.sleep_until_next_frame()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
    finally:
        cam.close()

if __name__ == "__main__":
    main()
