//
//  SyncPlayModalView.swift
//  Audia
//

import SwiftUI

struct SyncPlayModalView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    private let syncPlay = SyncPlayManager.shared
    @Namespace private var tabNamespace

    @State private var selectedTab: ModalTab = .host
    @State private var hostMode: HostMode = .cloud
    @State private var guestControlAllowed = false
    @State private var roomCodeInput = ""
    @State private var isEditingName = false
    @State private var showQRScanner = false
    @State private var copiedCode = false

    private var effectiveAccent: Color {
        settings.accentName == AccentPreset.all.first?.name ? AudiaTheme.primary : settings.accentColor
    }

    private var ctaForeground: Color {
        if settings.accentName == AccentPreset.all.first?.name {
            return colorScheme == .dark ? .black : .white
        }
        return .white
    }

    enum ModalTab: String, CaseIterable, Identifiable {
        case host = "Host"
        case join = "Join"
        var id: String { rawValue }
    }

    enum HostMode: String, CaseIterable, Identifiable {
        case cloud = "Cloud"
        case local = "Local Wi-Fi"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .cloud: return "icloud"
            case .local: return "wifi"
            }
        }
    }

    private var isConnecting: Bool {
        switch syncPlay.connectionState {
        case .connecting, .reconnecting: return true
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: 13) {
            headerBar

            if let session = syncPlay.session {
                activeSessionContent(session)
            } else {
                disconnectedContent
            }
        }
        .padding(18)
        .frame(maxWidth: 340)
        .audiaGlassCard(cornerRadius: 26, isInteractive: false)
        .shadow(color: Color.black.opacity(0.35), radius: 24, y: 10)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedTab)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isEditingName)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: syncPlay.session != nil)
        .onAppear {
            syncPlay.startDiscovery()
            syncPlay.resetConnectionState()
            isEditingName = settings.syncPlayGuestName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        .onDisappear {
            syncPlay.stopDiscovery()
        }
        .sheet(isPresented: $showQRScanner) {
            SyncPlayQRScannerSheet { code, scannedServer in
                let targetServer = scannedServer ?? settings.syncPlayServerUrl
                let name = settings.syncPlayGuestName.trimmingCharacters(in: .whitespacesAndNewlines)
                syncPlay.join(
                    serverUrl: targetServer,
                    roomCode: code,
                    guestName: name.isEmpty ? "Listener" : name
                )
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(effectiveAccent)

            Text("Listen Together")
                .font(.satoshi(.headline, weight: .bold))
                .foregroundStyle(AudiaTheme.textPrimary)

            if let session = syncPlay.session {
                Text("• \(session.participants.count)")
                    .font(.satoshi(.subheadline, weight: .semibold))
                    .foregroundStyle(AudiaTheme.textSecondary)
            }

            Spacer()

            Button {
                Haptics.light()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                    syncPlay.isModalPresented = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AudiaTheme.textPrimary)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
                    .audiaGlassCircle()
            }
            .buttonStyle(BouncyScaleButtonStyle(scale: 0.9))
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Disconnected State

    @ViewBuilder
    private var disconnectedContent: some View {
        if case .failed(let reason) = syncPlay.connectionState {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                Text(reason)
                    .font(.satoshi(.caption, weight: .medium))
                    .lineLimit(2)
                Spacer()
            }
            .foregroundStyle(.red)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }

        // Top Segmented Tabs (Host | Join)
        HStack(spacing: 4) {
            ForEach(ModalTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.satoshi(.subheadline, weight: isSelected ? .bold : .semibold))
                        .foregroundStyle(isSelected ? AudiaTheme.textPrimary : AudiaTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.primary.opacity(0.14))
                                    .matchedGeometryEffect(id: "syncTabIndicator", in: tabNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .audiaGlassCapsule(isInteractive: false)

        // Compact Name Pill or Inline Editor
        nameRow

        if selectedTab == .host {
            hostTabContent
        } else {
            joinTabContent
        }
    }

    @ViewBuilder
    private var nameRow: some View {
        let saved = settings.syncPlayGuestName.trimmingCharacters(in: .whitespacesAndNewlines)
        if isEditingName || saved.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "person.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(AudiaTheme.textSecondary)
                TextField("Your name", text: Binding(
                    get: { settings.syncPlayGuestName },
                    set: { settings.syncPlayGuestName = $0 }
                ))
                .textInputAutocapitalization(.words)
                .font(.satoshi(.subheadline))
                .onSubmit {
                    if !settings.syncPlayGuestName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        isEditingName = false
                    }
                }

                if !saved.isEmpty {
                    Button {
                        isEditingName = false
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(settings.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            HStack {
                Button {
                    isEditingName = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AudiaTheme.textSecondary)
                        Text(saved)
                            .font(.satoshi(.caption, weight: .semibold))
                            .foregroundStyle(AudiaTheme.textPrimary)
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundStyle(AudiaTheme.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.07))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
    }

    private var hostTabContent: some View {
        VStack(spacing: 12) {
            // Icon Pills for Cloud vs Local Wi-Fi (avoids duplicate segmented bars)
            HStack(spacing: 8) {
                ForEach(HostMode.allCases) { mode in
                    let isSelected = hostMode == mode
                    Button {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            hostMode = mode
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isSelected ? effectiveAccent : AudiaTheme.textSecondary)
                            Text(mode.rawValue)
                                .font(.satoshi(.caption, weight: .semibold))
                                .foregroundStyle(isSelected ? AudiaTheme.textPrimary : AudiaTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isSelected ? effectiveAccent.opacity(0.16) : Color.primary.opacity(0.05))
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? effectiveAccent.opacity(0.42) : Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(BouncyScaleButtonStyle(scale: 0.96))
                }
            }

            HStack {
                Text("Guest controls")
                    .font(.satoshi(.subheadline, weight: .medium))
                    .foregroundStyle(AudiaTheme.textPrimary)
                Spacer()
                Toggle("", isOn: $guestControlAllowed)
                    .labelsHidden()
                    .toggleStyle(.amoled)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                Haptics.medium()
                let name = settings.syncPlayGuestName.trimmingCharacters(in: .whitespacesAndNewlines)
                let hostName = name.isEmpty ? "Host" : name
                let roomSettings = SyncRoomSettings(guestControlAllowed: guestControlAllowed)
                if hostMode == .cloud {
                    syncPlay.startHost(
                        serverUrl: settings.syncPlayServerUrl,
                        hostName: hostName,
                        settings: roomSettings
                    )
                } else {
                    syncPlay.startLocalHost(hostName: hostName, settings: roomSettings)
                }
            } label: {
                HStack(spacing: 8) {
                    if isConnecting {
                        ProgressView()
                            .tint(ctaForeground)
                            .scaleEffect(0.85)
                    }
                    Text(isConnecting ? "Starting..." : "Start Session")
                        .font(.satoshi(.subheadline, weight: .bold))
                }
                .foregroundStyle(ctaForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(effectiveAccent)
                .clipShape(Capsule())
            }
            .disabled(isConnecting)
            .buttonStyle(BouncyScaleButtonStyle(scale: 0.97))
        }
    }

    @ViewBuilder
    private var joinTabContent: some View {
        VStack(spacing: 10) {
            if !syncPlay.discoveredSessions.isEmpty {
                ForEach(syncPlay.discoveredSessions) { discovered in
                    Button {
                        let name = settings.syncPlayGuestName.trimmingCharacters(in: .whitespacesAndNewlines)
                        syncPlay.join(
                            serverUrl: discovered.serverUrl,
                            roomCode: discovered.roomCode,
                            guestName: name.isEmpty ? "Listener" : name
                        )
                    } label: {
                        HStack {
                            Image(systemName: "wifi")
                                .font(.caption)
                                .foregroundStyle(settings.accentColor)
                            Text(discovered.hostName)
                                .font(.satoshi(.subheadline, weight: .semibold))
                                .foregroundStyle(AudiaTheme.textPrimary)
                            Text("(\(discovered.roomCode))")
                                .font(.satoshi(.caption))
                                .foregroundStyle(AudiaTheme.textSecondary)
                            Spacer()
                            Text("Join")
                                .font(.satoshi(.caption, weight: .bold))
                                .foregroundStyle(settings.accentColor)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.primary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                TextField("ROOM CODE", text: $roomCodeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.primary.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    if let raw = UIPasteboard.general.string {
                        let parsed = SyncPlayQRScannerSheet.parseQRPayload(raw)
                        if !parsed.roomCode.isEmpty {
                            let name = settings.syncPlayGuestName.trimmingCharacters(in: .whitespacesAndNewlines)
                            syncPlay.join(
                                serverUrl: parsed.serverUrl ?? settings.syncPlayServerUrl,
                                roomCode: parsed.roomCode,
                                guestName: name.isEmpty ? "Listener" : name
                            )
                        } else {
                            roomCodeInput = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        }
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AudiaTheme.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Paste code")

                Button {
                    showQRScanner = true
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AudiaTheme.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan QR")

                Button {
                    Haptics.medium()
                    let code = roomCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    guard !code.isEmpty else { return }
                    let name = settings.syncPlayGuestName.trimmingCharacters(in: .whitespacesAndNewlines)
                    syncPlay.join(
                        serverUrl: settings.syncPlayServerUrl,
                        roomCode: code,
                        guestName: name.isEmpty ? "Listener" : name
                    )
                } label: {
                    let isEmpty = roomCodeInput.trimmingCharacters(in: .whitespaces).isEmpty
                    Group {
                        if isConnecting {
                            ProgressView()
                                .tint(AudiaTheme.textPrimary)
                                .scaleEffect(0.85)
                                .frame(width: 56, height: 38)
                        } else {
                            Text("Join")
                                .font(.satoshi(.subheadline, weight: .bold))
                                .padding(.horizontal, 16)
                                .frame(height: 38)
                        }
                    }
                    .foregroundStyle(isEmpty ? AudiaTheme.textSecondary : ctaForeground)
                    .background(isEmpty ? Color.primary.opacity(0.08) : effectiveAccent)
                    .clipShape(Capsule())
                }
                .disabled(isConnecting || roomCodeInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Active Session State

    @ViewBuilder
    private func activeSessionContent(_ session: SyncRoomSnapshot) -> some View {
        let shareUrl = buildShareLink(for: session)

        HStack(spacing: 14) {
            SyncPlayQRCodeView(content: shareUrl, size: 72)

            VStack(alignment: .leading, spacing: 8) {
                Text(session.code)
                    .font(.system(size: 24, weight: .black, design: .monospaced))
                    .foregroundStyle(AudiaTheme.textPrimary)

                HStack(spacing: 8) {
                    Button {
                        UIPasteboard.general.string = session.code
                        copiedCode = true
                        Haptics.light()
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            copiedCode = false
                        }
                    } label: {
                        Label(copiedCode ? "Copied" : "Copy", systemImage: copiedCode ? "checkmark" : "doc.on.doc")
                            .font(.satoshi(.caption, weight: .semibold))
                            .foregroundStyle(AudiaTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    if let url = URL(string: shareUrl) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AudiaTheme.textPrimary)
                                .frame(width: 30, height: 30)
                                .background(Color.primary.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }

        // Compact participant chips
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(session.participants) { participant in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(participant.isOffline ? Color.gray : Color.green)
                            .frame(width: 6, height: 6)
                        Text(participant.name)
                            .font(.satoshi(.caption, weight: .medium))
                            .foregroundStyle(AudiaTheme.textPrimary)
                        if syncPlay.isHost && !participant.isHost {
                            Button {
                                syncPlay.kickParticipant(participant.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.red.opacity(0.85))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.07))
                    .clipShape(Capsule())
                }
            }
        }

        if syncPlay.isHost {
            HStack {
                Text("Guest controls")
                    .font(.satoshi(.subheadline, weight: .medium))
                    .foregroundStyle(AudiaTheme.textPrimary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { session.settings.guestControlAllowed },
                    set: { newVal in
                        var updated = session.settings
                        updated.guestControlAllowed = newVal
                        syncPlay.updateSettings(updated)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.amoled)
            }
        }

        Button {
            Haptics.medium()
            if syncPlay.isHost {
                syncPlay.endSession()
            } else {
                syncPlay.leave()
            }
        } label: {
            Text(syncPlay.isHost ? "End Session" : "Leave")
                .font(.satoshi(.subheadline, weight: .bold))
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.16))
                .overlay(Capsule().stroke(Color.red.opacity(0.35), lineWidth: 1))
                .clipShape(Capsule())
        }
        .buttonStyle(BouncyScaleButtonStyle(scale: 0.97))
    }

    private func buildShareLink(for session: SyncRoomSnapshot) -> String {
        if syncPlay.isLocalHosting, let localUrl = syncPlay.localServerUrl,
           let encoded = localUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            return "audia://syncplay/\(session.code)?server=\(encoded)"
        }
        let server = settings.syncPlayServerUrl
        if server != SyncPlayWebSocketClient.defaultServerUrl,
           let encoded = server.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            return "audia://syncplay/\(session.code)?server=\(encoded)"
        }
        return "audia://syncplay/\(session.code)"
    }
}
