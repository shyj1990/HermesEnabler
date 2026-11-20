import SwiftUI
import WatchConnectivity
import Darwin

/// WatchOS 11.x port research: runs read-only probes against the
/// MobileGestalt access path and shows the results. The write probe only
/// opens the cache file and closes it — nothing is ever modified.
struct DiagnosticsView: View {
    @State private var report: String = "Not run yet."
    @State private var sent: String = ""
    @State private var class2Parent: Bool = BQClass2ParentEnabled()
    @State private var acquire: Bool = BQAcquireEnabled()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("SYSTEM-LEVEL WRITE PATH PROBES")
                    .font(.headline)
                Text("Read-only. The write probe opens the MobileGestalt cache and closes it without writing anything.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Toggle("Class-2 parent fallback", isOn: Binding(
                    get: { class2Parent },
                    set: { newValue in
                        class2Parent = newValue
                        BQSetClass2ParentEnabled(newValue)
                    }
                ))
                .font(.footnote)
                Text("Experimental escape that needs no MCM-issued token for foreign containers. Some builds kill the process while moving Library — if that happens, the crash guard disables it automatically.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Toggle("Acquire extensions (older MCM)", isOn: Binding(
                    get: { acquire },
                    set: { newValue in
                        acquire = newValue
                        BQSetAcquireEnabled(newValue)
                    }
                ))
                .font(.footnote)
                Text("Calls container_acquire_sandbox_extension on every probe. OFF by default: calling it during the launch-time getter pass killed the app on watchOS 11.4. When ON, the first Run probes after a crash may disable it automatically.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(report)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Run probes & send report") {
                    runProbes()
                    sendReport()
                }
                if !sent.isEmpty {
                    Text(sent)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("Expected lines: build/os version, groups (0 = the signed app has no App Group entitlement — check the 'app group entitlement' line in the log tail), read (escape+read works), write (the go/no-go signal for a system-level unlock). If the backup alert appears, also try Settings → Class-2 fallback (experimental).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
        .navigationTitle("Diagnostics")
    }

    private func runProbes() {
        BQCoreInit()
        var full: String = BQDiagnosticsReport() as String? ?? "No report."
        if let logPath = BQLogPath() as String?,
           let log = try? String(contentsOfFile: logPath, encoding: .utf8),
           !log.isEmpty {
            // The escape chain logs every strategy it tries; the tail tells us
            // exactly which layers failed and with which codes.
            let tail = String(log.suffix(4000))
            full += "\n--- bqtool.log tail ---\n" + tail
        } else {
            full += "\n--- bqtool.log: empty or missing ---"
        }
        report = full
    }

    private func sendReport() {
        guard WCSession.isSupported() else {
            sent = "WCSession unsupported"
            return
        }
        let session = WCSession.default
        session.activate()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clocky-hermes-diagnostics.txt")
        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
            session.transferFile(url, metadata: [
                "type": "diagnosticsReport",
                "build": systemBuild() ?? "unknown"
            ])
            sent = "Report queued for transfer."
        } catch {
            sent = "Write failed: \(error.localizedDescription)"
        }
    }

    private func systemBuild() -> String? {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &value, &size, nil, 0)
        return String(cString: value)
    }
}
