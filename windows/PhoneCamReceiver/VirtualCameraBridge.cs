using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Text;

namespace PhoneCamReceiver;

/// <summary>
/// Steuert die mitgelieferte vcam_bridge.exe (siehe windows/vcam_bridge/),
/// die intern pyvirtualcam nutzt, um Frames in den OBS-Virtual-Camera-
/// Treiber zu schreiben. Der Prozess läuft komplett unsichtbar im
/// Hintergrund -- der Nutzer sieht kein Fenster und keine Konsole.
///
/// Voraussetzung: OBS (Version 28+) ist installiert und die "Virtual
/// Camera"-Funktion wurde mindestens einmal in OBS gestartet (das
/// registriert den Treiber im System). Danach muss OBS selbst nicht
/// mehr laufen.
/// </summary>
public sealed class VirtualCameraBridge : IDisposable
{
    public event Action<string>? StatusChanged;

    private Process? _process;
    private Stream? _stdin;
    private int _width;
    private int _height;
    private bool _ready;

    public bool IsReady => _ready;

    /// <summary>
    /// Pfad zur vcam_bridge.exe, die im gleichen Ordner wie diese App liegt.
    /// </summary>
    private static string BridgeExePath =>
        Path.Combine(AppContext.BaseDirectory, "vcam_bridge.exe");

    public bool Start(int width, int height, int fps)
    {
        if (!File.Exists(BridgeExePath))
        {
            StatusChanged?.Invoke(
                "vcam_bridge.exe nicht gefunden. Virtuelle Kamera ist deaktiviert; " +
                "die Vorschau funktioniert trotzdem normal.");
            return false;
        }

        _width = width;
        _height = height;

        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = BridgeExePath,
                UseShellExecute = false,
                RedirectStandardInput = true,
                RedirectStandardError = true,
                RedirectStandardOutput = true,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
            };

            _process = new Process { StartInfo = startInfo };
            _process.ErrorDataReceived += (_, e) =>
            {
                if (string.IsNullOrEmpty(e.Data)) return;
                HandleBridgeMessage(e.Data);
            };

            _process.Start();
            _process.BeginErrorReadLine();

            _stdin = _process.StandardInput.BaseStream;

            // Header-Zeile senden: "WIDTH HEIGHT FPS\n"
            var header = Encoding.ASCII.GetBytes($"{width} {height} {fps}\n");
            _stdin.Write(header, 0, header.Length);
            _stdin.Flush();

            StatusChanged?.Invoke("Virtuelle Kamera wird gestartet...");
            return true;
        }
        catch (Exception ex)
        {
            StatusChanged?.Invoke($"Virtuelle Kamera konnte nicht gestartet werden: {ex.Message}");
            return false;
        }
    }

    private void HandleBridgeMessage(string line)
    {
        if (line.StartsWith("READY"))
        {
            _ready = true;
            StatusChanged?.Invoke("Virtuelle Kamera aktiv (OBS Virtual Camera)");
        }
        else if (line.StartsWith("OBS_VCAM_NOT_AVAILABLE"))
        {
            _ready = false;
            StatusChanged?.Invoke(
                "OBS Virtual Camera nicht verfügbar. Bitte OBS öffnen, " +
                "einmal 'Virtuelle Kamera starten' klicken, dann wieder stoppen. " +
                "Danach erneut verbinden.");
        }
        else if (line.StartsWith("PYVIRTUALCAM_MISSING"))
        {
            _ready = false;
            StatusChanged?.Invoke("Interner Build-Fehler in vcam_bridge.exe.");
        }
        else
        {
            StatusChanged?.Invoke($"VCam: {line}");
        }
    }

    /// <summary>
    /// Schreibt ein Bitmap als rohe BGR24-Bytes in die Bridge.
    /// Größe muss exakt der beim Start angegebenen Breite/Höhe entsprechen.
    /// </summary>
    public void SendFrame(Bitmap bitmap)
    {
        if (_stdin == null || !_ready) return;
        if (bitmap.Width != _width || bitmap.Height != _height) return;

        try
        {
            var rect = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
            BitmapData bmpData = bitmap.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);

            int byteCount = bmpData.Stride * bmpData.Height;
            var buffer = new byte[byteCount];
            System.Runtime.InteropServices.Marshal.Copy(bmpData.Scan0, buffer, 0, byteCount);
            bitmap.UnlockBits(bmpData);

            // System.Drawing liefert Format24bppRgb tatsächlich als BGR im Speicher,
            // was exakt dem von pyvirtualcam erwarteten PixelFormat.BGR entspricht.
            _stdin.Write(buffer, 0, byteCount);
            _stdin.Flush();
        }
        catch (IOException)
        {
            // Bridge-Prozess wurde beendet oder Pipe ist kaputt
            _ready = false;
            StatusChanged?.Invoke("Verbindung zur virtuellen Kamera unterbrochen.");
        }
        catch (Exception)
        {
            // Best-effort Feature: einzelne Frame-Fehler ignorieren
        }
    }

    public void Stop()
    {
        try
        {
            _stdin?.Close();
            if (_process != null && !_process.HasExited)
            {
                _process.WaitForExit(1000);
                if (!_process.HasExited) _process.Kill();
            }
        }
        catch
        {
            // Best-effort Cleanup
        }
        finally
        {
            _process?.Dispose();
            _process = null;
            _stdin = null;
            _ready = false;
        }
    }

    public void Dispose() => Stop();
}
