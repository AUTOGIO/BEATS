import AppKit
import Foundation

struct Settings: Decodable {
    let defaultProfile: String?
    let defaultHeadphonesName: String?
    let defaultHeadphonesMac: String?
    let boom3DApp: String?
    let boom3DBundleID: String?
    let statusFilePath: String?

    enum CodingKeys: String, CodingKey {
        case defaultProfile = "default_profile"
        case defaultHeadphonesName = "default_headphones_name"
        case defaultHeadphonesMac = "default_headphones_mac"
        case boom3DApp = "boom_3d_app"
        case boom3DBundleID = "boom_3d_bundle_id"
        case statusFilePath = "status_file_path"
    }
}

struct StatusFile: Decodable {
    struct Profile: Decodable {
        let name: String?
    }

    struct Device: Decodable {
        let headphonesName: String?
        let headphonesMac: String?

        enum CodingKeys: String, CodingKey {
            case headphonesName = "headphones_name"
            case headphonesMac = "headphones_mac"
        }
    }

    struct Music: Decodable {
        let label: String?
        let kind: String?
    }

    struct Step: Decodable {
        let label: String
        let status: String
        let detail: String
    }

    let success: Bool
    let exitCode: Int
    let profile: Profile
    let device: Device
    let music: Music
    let steps: [Step]
}

final class BeatsStatusApp: NSObject, NSApplicationDelegate {
    private let repoRoot = "__REPO_ROOT__"
    private lazy var settingsURL = URL(fileURLWithPath: "\(repoRoot)/config/beats-settings.json")
    private let fallbackStatusURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/LockInAudioWorkflow/latest-status.json")

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var refreshTimer: Timer?
    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var watchedDescriptor: CInt = -1

    private let headlineItem = NSMenuItem(title: "Status: --", action: nil, keyEquivalent: "")
    private let profileItem = NSMenuItem(title: "Profile: --", action: nil, keyEquivalent: "")
    private let musicItem = NSMenuItem(title: "Music: --", action: nil, keyEquivalent: "")
    private let headphonesItem = NSMenuItem(title: "Headphones: --", action: nil, keyEquivalent: "")
    private let batteryItem = NSMenuItem(title: "Battery: unknown", action: nil, keyEquivalent: "")
    private let exitItem = NSMenuItem(title: "Last run: --", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "FB: --"

        menu = NSMenu()
        for item in [headlineItem, profileItem, musicItem, headphonesItem, batteryItem, exitItem] {
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshStatus), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let revealItem = NSMenuItem(title: "Reveal Status File", action: #selector(revealStatusFile), keyEquivalent: "")
        revealItem.target = self
        menu.addItem(revealItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        configureWatcher()
        refreshStatus()
        refreshTimer = Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(refreshStatus), userInfo: nil, repeats: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        directoryWatcher?.cancel()
        if watchedDescriptor >= 0 {
            close(watchedDescriptor)
            watchedDescriptor = -1
        }
    }

    private func loadSettings() -> Settings? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return try? JSONDecoder().decode(Settings.self, from: data)
    }

    private func currentStatusURL() -> URL {
        if let settings = loadSettings(),
           let path = settings.statusFilePath,
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: path)
        }
        return fallbackStatusURL
    }

    private func currentHeadphonesName() -> String {
        guard let value = loadSettings()?.defaultHeadphonesName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return "unknown"
        }
        return value
    }

    private func currentHeadphonesMac() -> String {
        guard let value = loadSettings()?.defaultHeadphonesMac?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return ""
        }
        return value
    }

    @objc private func refreshStatus() {
        let statusURL = currentStatusURL()
        guard let data = try? Data(contentsOf: statusURL),
              let status = try? JSONDecoder().decode(StatusFile.self, from: data) else {
            statusItem.button?.title = "FB: --"
            headlineItem.title = "Status: unknown"
            profileItem.title = "Profile: --"
            musicItem.title = "Music: --"
            headphonesItem.title = "Headphones: \(currentHeadphonesName())"
            batteryItem.title = "Battery: \(readBatteryDescription(name: currentHeadphonesName(), mac: currentHeadphonesMac()))"
            exitItem.title = "Last run: no status file"
            return
        }

        let profileName = status.profile.name ?? "Manual Session"
        let musicLabel = status.music.label ?? "Headphones Only"
        let headphonesName = status.device.headphonesName ?? currentHeadphonesName()
        let battery = readBatteryDescription(name: headphonesName, mac: status.device.headphonesMac ?? currentHeadphonesMac())
        let statusText = status.success ? "ok" : "error"

        statusItem.button?.title = "FB: \(shorten(profileName))"
        headlineItem.title = "Status: \(statusText)"
        profileItem.title = "Profile: \(profileName)"
        musicItem.title = "Music: \(musicLabel)"
        headphonesItem.title = "Headphones: \(headphonesName)"
        batteryItem.title = "Battery: \(battery)"
        exitItem.title = "Last run: exit \(status.exitCode)"
    }

    private func shorten(_ value: String) -> String {
        if value.count <= 14 { return value }
        return String(value.prefix(13)) + "…"
    }

    private func configureWatcher() {
        let directory = currentStatusURL().deletingLastPathComponent().path
        watchedDescriptor = open(directory, O_EVTONLY)
        guard watchedDescriptor >= 0 else { return }

        directoryWatcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: watchedDescriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: DispatchQueue.main
        )

        directoryWatcher?.setEventHandler { [weak self] in
            self?.refreshStatus()
        }
        directoryWatcher?.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.watchedDescriptor >= 0 {
                close(self.watchedDescriptor)
                self.watchedDescriptor = -1
            }
        }
        directoryWatcher?.resume()
    }

    private func readBatteryDescription(name: String, mac: String) -> String {
        let battery = readBatteryPercentage(name: name, mac: mac)
        if let battery {
            return "\(battery)%"
        }
        return "unknown"
    }

    private func readBatteryPercentage(name: String, mac: String) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let root = (object["SPBluetoothDataType"] as? [[String: Any]])?.first,
            let connected = root["device_connected"] as? [[String: Any]]
        else {
            return nil
        }

        for item in connected {
            for (deviceName, payload) in item {
                guard let details = payload as? [String: Any] else { continue }
                let address = (details["device_address"] as? String ?? "").lowercased()
                let normalizedMac = mac.lowercased()
                let normalizedName = name.lowercased()
                let matchesName = !normalizedName.isEmpty && deviceName.lowercased() == normalizedName
                let matchesMac = !normalizedMac.isEmpty && address == normalizedMac
                if matchesName || matchesMac {
                    if let percent = extractBattery(from: details) {
                        return percent
                    }
                }
            }
        }
        return nil
    }

    private func extractBattery(from dictionary: [String: Any]) -> Int? {
        for (key, value) in dictionary {
            let lowerKey = key.lowercased()
            if lowerKey.contains("battery") || lowerKey.contains("percent") {
                if let intValue = value as? Int {
                    return intValue
                }
                if let stringValue = value as? String,
                   let percent = parseBatteryPercent(stringValue) {
                    return percent
                }
            }
            if let child = value as? [String: Any], let nested = extractBattery(from: child) {
                return nested
            }
        }
        return nil
    }

    private func parseBatteryPercent(_ string: String) -> Int? {
        let digits = string.filter(\.isNumber)
        guard let number = Int(digits), (0...100).contains(number) else { return nil }
        return number
    }

    @objc private func revealStatusFile() {
        let statusURL = currentStatusURL()
        if FileManager.default.fileExists(atPath: statusURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([statusURL])
        } else {
            NSWorkspace.shared.open(statusURL.deletingLastPathComponent())
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = BeatsStatusApp()
app.delegate = delegate
app.run()
