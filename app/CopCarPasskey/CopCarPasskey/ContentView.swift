import SwiftUI
import VisionKit

struct ContentView: View {
    @EnvironmentObject var central: PasskeyCentral
    @EnvironmentObject var enrollment: EnrollmentManager
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            ZStack {
                background
                content
            }
            .sheet(isPresented: $showScanner) {
                if DataScannerViewController.isAvailable {
                    QRScannerView { payload in
                        showScanner = false
                        guard let url = URL(string: payload) else {
                            enrollment.enrollmentError = "QR code did not contain a valid URL"
                            return
                        }
                        do {
                            try enrollment.enroll(from: url)
                            WatchSyncManager.shared.pushSecretToWatch()
                        } catch {
                            enrollment.enrollmentError = error.localizedDescription
                        }
                    }
                } else {
                    ContentUnavailableView("Scanner Unavailable",
                        systemImage: "qrcode.viewfinder",
                        description: Text("This device does not support the QR scanner."))
                }
            }
            .alert("Enrollment Failed", isPresented: Binding(
                get: { enrollment.enrollmentError != nil },
                set: { if !$0 { enrollment.enrollmentError = nil } }
            )) {
                Button("OK", role: .cancel) { enrollment.enrollmentError = nil }
            } message: {
                Text(enrollment.enrollmentError ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("CopCar Passkey")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                    }
                }
            }
        }
    }

    private var background: some View {
        ZStack {
            Image("AppBackground")
                .resizable()
                .scaledToFill()
            Color.black.opacity(0.40)
            LinearGradient(
                colors: [.clear, .black.opacity(0.3)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var ringColor: Color {
        if central.isAuthenticating { return .yellow }
        if central.isKeyPresent     { return .green }
        if central.isConnected      { return .blue }
        if central.isScanning       { return .green }
        return .gray
    }

    private var ringOpacity: Double {
        if central.isAuthenticating { return 0.5 }
        if central.isKeyPresent     { return 0.5 }
        if central.isConnected      { return 0.35 }
        if central.isScanning       { return 0.35 }
        return 0.12
    }

    private var statusText: String {
        if !central.isEnabled       { return "Key Off" }
        if central.isAuthenticating { return "Authenticating…" }
        if central.isKeyPresent     { return "Key Present" }
        if central.isConnected      { return "Connected" }
        if central.isScanning       { return "Scanning" }
        return "Inactive"
    }

    private var content: some View {
        VStack(spacing: 32) {
            // Status ring
            ZStack {
                Circle()
                    .stroke(ringColor.opacity(ringOpacity), lineWidth: 20)
                    .frame(width: 160, height: 160)

                Image(systemName: enrollment.isEnrolled ? "key.fill" : "key.slash")
                    .font(.system(size: 52))
                    .foregroundStyle(ringColor)
                    .symbolEffect(.pulse, isActive: central.isAuthenticating)
            }

            VStack(spacing: 6) {
                Text(statusText)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .animation(.default, value: statusText)
                if enrollment.isEnrolled {
                    Text(enrollment.enrolledLabel)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Text(central.lastEvent)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            if enrollment.isEnrolled {
                Toggle(isOn: Binding(
                    get: { central.isEnabled },
                    set: { $0 ? central.enable() : central.disable() }
                )) {
                    Label("Key Active", systemImage: "key.fill")
                        .foregroundStyle(.white)
                }
                .toggleStyle(.switch)
                .tint(.green)
                .padding(.horizontal, 48)
            }

            if !enrollment.isEnrolled {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Text("No key enrolled")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Scan the QR code from the admin portal to enroll your device.")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.15))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 32)
            }
        }
        .padding()
    }
}
