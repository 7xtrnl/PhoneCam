using System.IO;
using System.Net.Sockets;

namespace PhoneCamReceiver;

/// <summary>
/// Verbindet sich per TCP mit der PhoneCam iOS-App und liest fortlaufend
/// JPEG-Frames im Format [4 Byte Big-Endian Länge][JPEG-Bytes].
/// Das entspricht exakt dem Sende-Format aus FrameStreamServer.swift.
/// </summary>
public sealed class FrameStreamClient : IDisposable
{
    public event Action<byte[]>? FrameReceived;
    public event Action<string>? StatusChanged;
    public event Action<double>? BitrateUpdated; // KB/s

    private TcpClient? _client;
    private CancellationTokenSource? _cts;
    private long _bytesReceivedSinceLastTick;
    private Timer? _bitrateTimer;

    public bool IsConnected => _client?.Connected ?? false;

    public async Task ConnectAsync(string host, int port)
    {
        Disconnect();

        _cts = new CancellationTokenSource();
        var token = _cts.Token;

        try
        {
            StatusChanged?.Invoke("Verbinde...");
            _client = new TcpClient();
            _client.NoDelay = true; // Latenz wichtiger als Paket-Effizienz
            _client.ReceiveBufferSize = 1 << 20; // 1 MB

            await _client.ConnectAsync(host, port, token);
            StatusChanged?.Invoke("Verbunden");

            StartBitrateTimer();
            _ = Task.Run(() => ReceiveLoopAsync(_client.GetStream(), token), token);
        }
        catch (Exception ex)
        {
            StatusChanged?.Invoke($"Verbindung fehlgeschlagen: {ex.Message}");
            Disconnect();
        }
    }

    public void Disconnect()
    {
        _cts?.Cancel();
        _cts = null;
        _bitrateTimer?.Dispose();
        _bitrateTimer = null;
        _client?.Close();
        _client?.Dispose();
        _client = null;
        StatusChanged?.Invoke("Getrennt");
    }

    private async Task ReceiveLoopAsync(NetworkStream stream, CancellationToken token)
    {
        var lengthBuffer = new byte[4];

        try
        {
            while (!token.IsCancellationRequested)
            {
                await ReadExactAsync(stream, lengthBuffer, 4, token);

                // Big-Endian UInt32 lesen (passend zu Swifts .bigEndian)
                int frameLength =
                    (lengthBuffer[0] << 24) |
                    (lengthBuffer[1] << 16) |
                    (lengthBuffer[2] << 8) |
                     lengthBuffer[3];

                if (frameLength <= 0 || frameLength > 20_000_000)
                {
                    // Unplausible Länge -> Verbindung ist wahrscheinlich korrupt
                    StatusChanged?.Invoke("Ungültiges Frame empfangen, trenne Verbindung");
                    break;
                }

                var frameBuffer = new byte[frameLength];
                await ReadExactAsync(stream, frameBuffer, frameLength, token);

                Interlocked.Add(ref _bytesReceivedSinceLastTick, frameLength + 4);
                FrameReceived?.Invoke(frameBuffer);
            }
        }
        catch (OperationCanceledException)
        {
            // Normales Trennen, kein Fehler
        }
        catch (Exception ex)
        {
            StatusChanged?.Invoke($"Verbindung verloren: {ex.Message}");
        }
        finally
        {
            StatusChanged?.Invoke("Getrennt");
        }
    }

    private static async Task ReadExactAsync(Stream stream, byte[] buffer, int count, CancellationToken token)
    {
        int offset = 0;
        while (offset < count)
        {
            int read = await stream.ReadAsync(buffer.AsMemory(offset, count - offset), token);
            if (read == 0)
            {
                throw new IOException("Verbindung vom Server geschlossen.");
            }
            offset += read;
        }
    }

    private void StartBitrateTimer()
    {
        _bitrateTimer = new Timer(_ =>
        {
            long bytes = Interlocked.Exchange(ref _bytesReceivedSinceLastTick, 0);
            BitrateUpdated?.Invoke(bytes / 1024.0);
        }, null, 1000, 1000);
    }

    public void Dispose() => Disconnect();
}
