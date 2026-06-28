import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var server = FrameStreamServer(port: 5050)

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showSettings = false
    @State private var isFullScreen = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isFullScreen {
                fullScreenPreview
            } else {
                VStack(spacing: 0) {
                    statusBar

                    previewArea
                        .frame(maxHeight: .infinity)

                    controlPanel
                }
            }
        }
        .statusBarHidden(isFullScreen)
        .onAppear {
            camera.onJPEGFrame = { [weak server] data in
                server?.send(jpegData: data)
            }
            camera.start()
            server.start()
        }
        .onDisappear {
            camera.stop()
            server.stop()
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(camera: camera, server: server)
        }
    }

    // MARK: - Vollbildmodus (randlos, Querformat)

    private var fullScreenPreview: some View {
        GeometryReader { geo in
            ZStack {
                if let image = camera.lastPreviewImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Color.black
                }

                // Unsichtbare Tap-Fläche, um zurück zur normalen Ansicht zu kommen
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            isFullScreen = false
                        } label: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .padding(12)
                                .background(.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                        .padding()
                    }
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
        .rotationEffect(.degrees(90))
        .frame(
            width: UIScreen.main.bounds.height,
            height: UIScreen.main.bounds.width
        )
        // Die View wird gedreht und in vertauschten Dimensionen gerahmt,
        // damit sie auf dem Hochformat-Bildschirm wie ein echtes Querformat
        // wirkt, ohne dass die System-Orientierung selbst gewechselt werden muss
        // (vermeidet Re-Layout-Sprünge anderer SwiftUI-Views im Hintergrund).
    }

    // MARK: - Status-Leiste

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(server.isListening ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            Text(server.isListening ? "Server läuft" : "Server gestoppt")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if server.connectedClientCount > 0 {
                Label("PC verbunden", systemImage: "desktopcomputer")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Text("IP: \(server.localIPAddress) : \(server.port.rawValue)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Button {
                isFullScreen = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .foregroundStyle(.white)
            }

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color.black.opacity(0.6))
    }

    // MARK: - Vorschau

    private var previewArea: some View {
        ZStack {
            if let image = camera.lastPreviewImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView("Kamera startet…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }

            if camera.stillImageOverride != nil {
                VStack {
                    Spacer()
                    Text("Standbild-Modus aktiv")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.orange.opacity(0.85))
                        .clipShape(Capsule())
                        .padding(.bottom, 12)
                }
            }
        }
    }

    // MARK: - Steuerung unten

    private var controlPanel: some View {
        VStack(spacing: 16) {
            // Zoom-Slider
            HStack {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundStyle(.white)
                Slider(
                    value: Binding(
                        get: { camera.zoomFactor },
                        set: { camera.setZoom($0) }
                    ),
                    in: camera.minZoom...camera.maxZoom
                )
                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(.white)
                Text(String(format: "%.1fx", camera.zoomFactor))
                    .font(.caption.monospaced())
                    .foregroundStyle(.white)
                    .frame(width: 40)
            }
            .padding(.horizontal)

            // Haupt-Buttons
            HStack(spacing: 28) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    controlButton(icon: "photo.on.rectangle", label: "Galerie")
                }
                .onChange(of: selectedPhotoItem) { newItem in
                    Task { await loadPickedImage(newItem) }
                }

                Button {
                    camera.stillImageOverride = nil
                } label: {
                    controlButton(
                        icon: "video.fill",
                        label: "Live-Kamera",
                        highlighted: camera.stillImageOverride == nil
                    )
                }

                Button {
                    camera.switchCamera()
                } label: {
                    controlButton(icon: "arrow.triangle.2.circlepath.camera", label: "Wechseln")
                }
            }
            .padding(.bottom, 24)
        }
        .padding(.top, 12)
        .background(Color.black.opacity(0.85))
    }

    private func controlButton(icon: String, label: String, highlighted: Bool = false) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(highlighted ? .green : .white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 70)
    }

    private func loadPickedImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let uiImage = UIImage(data: data) {
            camera.stillImageOverride = uiImage
        }
    }
}

// MARK: - Einstellungen (FPS, Qualität, Auflösung, Port)

struct SettingsSheet: View {
    @ObservedObject var camera: CameraManager
    @ObservedObject var server: FrameStreamServer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Bildqualität") {
                    Picker("Auflösung", selection: $camera.resolutionPreset) {
                        ForEach(CameraManager.ResolutionPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("JPEG-Qualität: \(Int(camera.jpegQuality * 100))%")
                        Slider(value: $camera.jpegQuality, in: 0.2...1.0)
                    }
                }

                Section("Performance") {
                    VStack(alignment: .leading) {
                        Text("Ziel-FPS: \(camera.targetFPS)")
                        Slider(
                            value: Binding(
                                get: { Double(camera.targetFPS) },
                                set: { camera.targetFPS = Int($0) }
                            ),
                            in: 5...60,
                            step: 1
                        )
                    }
                    Text("Höhere FPS und Qualität benötigen mehr WLAN-Bandbreite. Bei Rucklern: FPS oder Qualität reduzieren.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Verbindung") {
                    HStack {
                        Text("IP-Adresse")
                        Spacer()
                        Text(server.localIPAddress)
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }
                    HStack {
                        Text("Port")
                        Spacer()
                        Text("\(server.port.rawValue)")
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }
                    HStack {
                        Text("Übertragung")
                        Spacer()
                        Text(formattedBandwidth)
                            .foregroundStyle(.secondary)
                    }
                    Text("Trage diese IP-Adresse und den Port im PC-Programm ein, um die Verbindung herzustellen. iPhone und PC müssen im selben WLAN sein.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Einstellungen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    private var formattedBandwidth: String {
        let kb = server.bytesPerSecond / 1024
        return String(format: "%.0f KB/s", kb)
    }
}

#Preview {
    ContentView()
}
