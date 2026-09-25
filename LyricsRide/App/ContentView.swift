import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var session: LyricsSession
    @EnvironmentObject private var spotify: SpotifyManager
    @EnvironmentObject private var driveMode: DriveModeManager
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                nowPlaying
                if spotify.snapshot != nil {
                    if !session.lyrics.isEmpty {
                        lyricsList
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .onOpenURL { spotify.handleOpenURL($0) }
        .onChange(of: spotify.snapshot) { track in
            if let track {
                session.useSpotify(track)
                if driveMode.isRunning && !session.liveActivityIsRunning {
                    session.startLiveActivity()
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private var nowPlaying: some View {
        VStack(spacing: 18) {
            HStack(spacing: 16) {
                Group {
                    if let artwork = spotify.artwork {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(Image(systemName: "music.note").font(.system(size: 52)).foregroundStyle(.white))
                    }
                }
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(spotify.snapshot == nil ? "Nenhuma música tocando" : session.title)
                        .font(.title3.bold())
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.white)
                    Text(spotify.snapshot == nil ? "Spotify" : session.artist)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)

                    Text(session.isPlaying ? "Tocando agora" : "Pausado")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(spotify.snapshot == nil ? Color.white.opacity(0.45) : (session.isPlaying ? Color.white : Color.white.opacity(0.65)))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 0) {
                Button(action: spotify.skipToPrevious) {
                    Image(systemName: "backward.fill")
                        .frame(maxWidth: .infinity, minHeight: 72)
                }
                .accessibilityLabel("Música anterior")

                Button(action: spotify.togglePlayback) {
                    Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 72)
                }
                .accessibilityLabel(session.isPlaying ? "Pausar" : "Reproduzir")

                Button(action: spotify.skipToNext) {
                    Image(systemName: "forward.fill")
                        .frame(maxWidth: .infinity, minHeight: 72)
                }
                .accessibilityLabel("Próxima música")
            }
            .font(.system(size: 38, weight: .semibold))
            .buttonStyle(.plain)
            .disabled(spotify.snapshot == nil)
            .foregroundStyle(spotify.snapshot == nil ? Color.white.opacity(0.35) : Color.white)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: playerGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
    }

    private var playerGradientColors: [Color] {
        let fallback = UIColor(red: 0.05, green: 0.39, blue: 0.54, alpha: 1)
        let albumColor = spotify.artworkTint ?? fallback
        return [
            Color(uiColor: albumColor.playerSurfaceColor(brightnessMultiplier: 0.76)),
            Color(uiColor: albumColor.playerSurfaceColor(brightnessMultiplier: 0.34))
        ]
    }

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Configurações", systemImage: "slider.horizontal.3")
                .font(.headline)

            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spotify").font(.subheadline.weight(.semibold))
                    Text(spotify.status)
                        .font(.caption)
                        .foregroundStyle(spotify.isConnected ? .green : .secondary)
                }
                Spacer()
                Button(spotify.isConnected ? "Conectado" : "Conectar", action: spotify.connect)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(spotify.isConnected)
            }

            Divider()

            HStack(spacing: 12) {
                Image(systemName: "car.fill")
                    .foregroundStyle(.blue)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Modo Direção").font(.subheadline.weight(.semibold))
                    Text("Mantém a letra no CarPlay")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { driveMode.isRunning },
                    set: { enabled in
                        if enabled {
                            if spotify.snapshot != nil && !session.liveActivityIsRunning { session.startLiveActivity() }
                            driveMode.start()
                        } else {
                            driveMode.stop()
                        }
                    }
                ))
                .labelsHidden()
                .tint(.blue)
            }

            Divider()

            HStack(spacing: 12) {
                Image(systemName: "rectangle.topthird.inset.filled")
                    .foregroundStyle(.pink)
                    .frame(width: 20)
                Text("Live Activity")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(session.liveActivityIsRunning ? "Encerrar" : "Mostrar") {
                    session.liveActivityIsRunning ? session.stopLiveActivity() : session.startLiveActivity()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!session.liveActivityIsRunning && spotify.snapshot == nil)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
    }

    private var spotifyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Conectar Spotify", systemImage: "dot.radiowaves.left.and.right")
                .font(.headline)
            Text(spotify.status)
                .font(.footnote)
                .foregroundStyle(spotify.isConnected ? .green : .secondary)
            Button(spotify.isConnected ? "Spotify conectado" : "Conectar minha conta", action: spotify.connect)
                .buttonStyle(.borderedProminent)
                .disabled(spotify.isConnected)
                .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var liveActivityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Live Activity", systemImage: "rectangle.topthird.inset.filled")
                .font(.headline)
            Button(session.liveActivityIsRunning ? "Encerrar Live Activity" : "Mostrar letras dinâmicas") {
                session.liveActivityIsRunning ? session.stopLiveActivity() : session.startLiveActivity()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!session.liveActivityIsRunning && spotify.snapshot == nil)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
    }

    private var driveModeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Modo Direção", systemImage: "car.fill")
                .font(.headline)
            Text("Mantém a letra no CarPlay")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Toggle("", isOn: Binding(
                get: { driveMode.isRunning },
                set: { enabled in
                    if enabled {
                        if spotify.snapshot != nil && !session.liveActivityIsRunning { session.startLiveActivity() }
                        driveMode.start()
                    } else {
                        driveMode.stop()
                    }
                }
            ))
            .labelsHidden()
            .tint(.blue)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
    }

    private var lyricsList: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 14) {
                Label("Letra", systemImage: "music.note.list")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(session.lyrics) { line in
                            let isCurrent = line == session.currentLine
                            Text(line.text)
                                .font(.system(size: isCurrent ? 26 : 20, weight: isCurrent ? .bold : .medium))
                                .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.65)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, isCurrent ? 10 : 6)
                            .id(line.id)
                            .animation(.easeInOut(duration: 0.3), value: isCurrent)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: .infinity)
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .onAppear {
                    proxy.scrollTo(session.currentLine.id, anchor: .center)
                }
                .onChange(of: session.currentLine.id) { lineID in
                    withAnimation(.easeInOut(duration: 0.45)) {
                        proxy.scrollTo(lineID, anchor: .center)
                    }
                }
            }
        }
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: LyricsSession
    @EnvironmentObject private var spotify: SpotifyManager
    @EnvironmentObject private var driveMode: DriveModeManager
    @State private var appIcon = AppIconChoice.current
    @State private var iconError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Label(spotify.isConnected ? "Spotify conectado" : "Spotify", systemImage: spotify.isConnected ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right")
                            .foregroundStyle(spotify.isConnected ? .green : .primary)
                        Spacer()
                        Button(spotify.isConnected ? "Desconectar" : "Conectar") {
                            if spotify.isConnected { spotify.disconnect() }
                            else { spotify.connect() }
                        }
                    }

                    Toggle("Live Activity", isOn: Binding(
                        get: { driveMode.isRunning },
                        set: { enabled in
                            if enabled {
                                driveMode.start()
                                if spotify.snapshot != nil && !session.liveActivityIsRunning {
                                    session.startLiveActivity()
                                }
                            } else {
                                driveMode.stop()
                                session.stopLiveActivity()
                            }
                        }
                    ))
                }
                Section("Ícone do app") {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(AppIconChoice.allCases) { icon in
                            Button { appIcon = icon } label: {
                                VStack(spacing: 8) {
                                    ZStack(alignment: .topTrailing) {
                                        Image(icon.previewAssetName)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 64, height: 64)
                                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                                        if appIcon == icon {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.title3)
                                                .foregroundStyle(.blue, .white)
                                                .offset(x: 7, y: -7)
                                        }
                                    }
                                    Text(icon.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    appIcon == icon ? Color.accentColor.opacity(0.12) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
            .navigationTitle("Configurações")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Concluído") { dismiss() }
                }
            }
        }
        .onChange(of: appIcon) { newIcon in
            UIApplication.shared.setAlternateIconName(newIcon.alternateIconName) { error in
                if let error { iconError = error.localizedDescription }
            }
        }
        .alert("Não foi possível trocar o ícone", isPresented: Binding(
            get: { iconError != nil },
            set: { if !$0 { iconError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(iconError ?? "Erro desconhecido")
        }
    }
}

private enum AppIconChoice: String, CaseIterable, Identifiable {
    case defaultIcon
    case green

    var id: String { rawValue }

    var title: String {
        switch self {
        case .defaultIcon: "Padrão"
        case .green: "Verde"
        }
    }

    var previewAssetName: String {
        switch self {
        case .defaultIcon: "IconPreviewDefault"
        case .green: "IconPreviewGreen"
        }
    }

    var alternateIconName: String? {
        switch self {
        case .defaultIcon: nil
        case .green: "AppIconGreen"
        }
    }

    static var current: AppIconChoice {
        UIApplication.shared.alternateIconName == "AppIconGreen" ? .green : .defaultIcon
    }
}
