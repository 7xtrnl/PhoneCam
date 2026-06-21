using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Windows;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace PhoneCamReceiver;

public partial class MainWindow : Window
{
    private readonly FrameStreamClient _client = new();
    private readonly VirtualCameraBridge _vcamBridge = new();

    private bool _vcamStarted;
    private int _expectedWidth = 1280;
    private int _expectedHeight = 720;

    public MainWindow()
    {
        InitializeComponent();

        _client.StatusChanged += OnClientStatusChanged;
        _client.FrameReceived += OnFrameReceived;
        _client.BitrateUpdated += OnBitrateUpdated;
        _vcamBridge.StatusChanged += OnVCamStatusChanged;

        Closing += (_, _) =>
        {
            _client.Disconnect();
            _vcamBridge.Stop();
        };
    }

    private async void ConnectButton_Click(object sender, RoutedEventArgs e)
    {
        if (_client.IsConnected)
        {
            _client.Disconnect();
            _vcamBridge.Stop();
            _vcamStarted = false;
            ConnectButton.Content = "Verbinden";
            return;
        }

        string host = IpAddressBox.Text.Trim();
        if (!int.TryParse(PortBox.Text.Trim(), out int port))
        {
            StatusText.Text = "Ungültiger Port.";
            return;
        }

        (_expectedWidth, _expectedHeight) = ResolutionCombo.SelectedIndex switch
        {
            0 => (640, 480),
            2 => (1920, 1080),
            _ => (1280, 720),
        };

        ConnectButton.Content = "Verbinden...";
        await _client.ConnectAsync(host, port);
    }

    private void VirtualCamCheckbox_Changed(object sender, RoutedEventArgs e)
    {
        // Wird beim nächsten Frame berücksichtigt; kein sofortiger Neustart nötig.
        if (VirtualCamCheckbox.IsChecked != true)
        {
            _vcamBridge.Stop();
            _vcamStarted = false;
            VCamStatusText.Text = "Deaktiviert";
        }
    }

    private void OnClientStatusChanged(string status)
    {
        Dispatcher.Invoke(() =>
        {
            StatusText.Text = status;
            if (status == "Verbunden")
            {
                ConnectButton.Content = "Trennen";
            }
            else if (status == "Getrennt")
            {
                ConnectButton.Content = "Verbinden";
                NoSignalText.Visibility = Visibility.Visible;
            }
        });
    }

    private void OnBitrateUpdated(double kbPerSecond)
    {
        Dispatcher.Invoke(() =>
        {
            BitrateText.Text = $"{kbPerSecond:0} KB/s";
        });
    }

    private void OnVCamStatusChanged(string status)
    {
        Dispatcher.Invoke(() => VCamStatusText.Text = status);
    }

    /// <summary>
    /// Wird für jeden empfangenen JPEG-Frame aufgerufen (auf einem Hintergrund-Thread).
    /// Dekodiert das JPEG, zeigt es in der Vorschau und reicht es ggf. an die
    /// virtuelle Kamera weiter.
    /// </summary>
    private void OnFrameReceived(byte[] jpegBytes)
    {
        try
        {
            using var ms = new MemoryStream(jpegBytes);
            using var bitmap = new Bitmap(ms);

            // Virtuelle Kamera bei Bedarf lazy starten, sobald wir die
            // tatsächliche Frame-Größe kennen.
            if (VirtualCamCheckbox.IsChecked == true && !_vcamStarted)
            {
                int fps = (int)Dispatcher.Invoke(() => FpsSlider.Value);
                bool started = _vcamBridge.Start(bitmap.Width, bitmap.Height, fps);
                _vcamStarted = started;
            }

            if (_vcamStarted)
            {
                _vcamBridge.SendFrame(bitmap);
            }

            // UI-Vorschau aktualisieren (auf UI-Thread, throttled über Dispatcher-Priorität)
            var bitmapImage = ConvertToBitmapImage(bitmap);
            Dispatcher.BeginInvoke(DispatcherPriority.Render, () =>
            {
                PreviewImage.Source = bitmapImage;
                NoSignalText.Visibility = Visibility.Collapsed;
            });
        }
        catch (Exception)
        {
            // Beschädigter Frame -> einfach überspringen, nächster Frame kommt gleich
        }
    }

    private static BitmapImage ConvertToBitmapImage(Bitmap bitmap)
    {
        using var memory = new MemoryStream();
        bitmap.Save(memory, ImageFormat.Bmp);
        memory.Position = 0;

        var bitmapImage = new BitmapImage();
        bitmapImage.BeginInit();
        bitmapImage.CacheOption = BitmapCacheOption.OnLoad;
        bitmapImage.StreamSource = memory;
        bitmapImage.EndInit();
        bitmapImage.Freeze(); // Thread-sicher für Cross-Thread-Zugriff
        return bitmapImage;
    }
}
