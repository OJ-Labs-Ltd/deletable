import SwiftUI

/// How safe it is to delete something.
enum RiskLevel: Int, Comparable {
    case safe = 0        // regenerated automatically, nothing is lost
    case redownload      // safe, but gets downloaded/rebuilt again (time and bandwidth)
    case review          // could be something you want: look before deleting
    case unknown         // Deletable has no rule for this
    case danger          // app data, system files, personal libraries: don't delete here

    static func < (a: RiskLevel, b: RiskLevel) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .safe: return "Safe"
        case .redownload: return "Safe · re-downloads"
        case .review: return "Review first"
        case .unknown: return "Unknown"
        case .danger: return "High risk"
        }
    }

    var color: Color {
        switch self {
        case .safe: return Color(red: 0.30, green: 0.82, blue: 0.45)
        case .redownload: return Color(red: 0.35, green: 0.70, blue: 1.0)
        case .review: return Color(red: 1.0, green: 0.72, blue: 0.25)
        case .unknown: return Color(white: 0.6)
        case .danger: return Color(red: 1.0, green: 0.36, blue: 0.36)
        }
    }

    var symbol: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .redownload: return "arrow.down.circle.fill"
        case .review: return "eye.fill"
        case .unknown: return "questionmark.circle.fill"
        case .danger: return "exclamationmark.octagon.fill"
        }
    }
}

struct RiskAssessment {
    let level: RiskLevel
    let reason: String
}

/// Rule-based guess at what a path is and whether deleting it is safe.
/// The deepest matching folder wins, so `~/Documents/app/node_modules` is judged as
/// node_modules, not as Documents.
enum RiskAssessor {
    private typealias Rule = (RiskLevel, String)

    private static let home = Demo.homeURL.standardizedFileURL.path

    /// Exact paths. "~" is the home folder.
    private static let pathRules: [String: Rule] = {
        let r: [(String, RiskLevel, String)] = [
            // --- System
            ("/", .danger, "The whole disk."),
            ("/System", .danger, "macOS system files. Protected and required."),
            ("/usr", .danger, "Unix system files and command-line tools."),
            ("/bin", .danger, "Core system commands."),
            ("/sbin", .danger, "Core system commands."),
            ("/private", .danger, "System data managed by macOS."),
            ("/private/var/folders", .danger, "Per-user temp files managed by macOS; it clears them itself."),
            ("/Library", .danger, "System-wide app support, fonts and extensions. Deleting parts can break apps."),
            ("/opt/homebrew", .review, "Homebrew and the tools it installed. Use `brew cleanup` / `brew uninstall` instead."),
            ("/opt/homebrew/Caskroom", .review, "Installers Homebrew kept. `brew cleanup` removes old ones safely."),
            ("/Applications/microchip", .review, "Microchip MPLAB X IDE and XC compilers. Use the uninstallers inside (Uninstall_MPLAB_X_IDE…) so drivers and helpers are removed too."),
            ("/Applications/Xcode.app", .review, "Xcode. Reinstall from the App Store if removed; DerivedData and simulators are the usual space hogs."),
            ("/Applications", .review, "Installed apps. Removing an app is fine if you don't use it, but its data stays in ~/Library."),
            ("/Users", .danger, "All user accounts."),

            // --- Home: personal
            ("~", .danger, "Your home folder."),
            ("~/Documents", .review, "Your documents."),
            ("~/Desktop", .review, "Files on your Desktop."),
            ("~/Downloads", .review, "Downloads. Old installers (.dmg/.pkg/.zip) are usually safe once used."),
            ("~/Movies", .review, "Your videos and video-editing projects."),
            ("~/Music", .review, "Your music library."),
            ("~/Pictures", .review, "Your pictures."),
            ("~/Pictures/Photos Library.photoslibrary", .danger, "Your Photos library. Delete photos inside the Photos app, never here."),
            ("~/My Drive", .danger, "Google Drive. Deleting here deletes from Google Drive everywhere."),
            ("~/.Trash", .review, "Items already in the Trash. Emptying deletes them permanently."),

            // --- Home: Library
            ("~/Library", .danger, "App settings and data. Only specific subfolders are safe to clear."),
            ("~/Library/Caches", .safe, "App caches. Apps rebuild these; quit large apps before clearing."),
            ("~/Library/Logs", .safe, "Log files. Only useful for diagnosing problems."),
            ("~/Library/Application Support", .danger, "Apps' saved data and settings. Deleting can lose data or reset apps."),
            ("~/Library/Application Support/MobileSync/Backup", .review, "iPhone/iPad backups. Delete old ones from Finder › your device › Manage Backups."),
            ("~/Library/Containers", .danger, "Sandboxed apps' data (documents, settings, offline content)."),
            ("~/Library/Containers/com.docker.docker", .review, "Docker images, containers and volumes. Use `docker system prune` or Docker Desktop's cleanup instead."),
            ("~/Library/Group Containers", .danger, "Data shared between apps (e.g. Office, Messages)."),
            ("~/Library/Mail", .danger, "Your Mail messages and attachments."),
            ("~/Library/Messages", .danger, "Your Messages history and attachments."),
            ("~/Library/Mobile Documents", .danger, "iCloud Drive. Deleting here deletes from iCloud on all devices."),
            ("~/Library/CloudStorage", .danger, "Cloud drives (Google Drive, OneDrive, Dropbox). Deleting here deletes in the cloud."),
            ("~/Library/Keychains", .danger, "Your passwords and certificates."),
            ("~/Library/Preferences", .danger, "App settings. Small, and deleting resets apps."),
            ("~/Library/Developer/Xcode/DerivedData", .safe, "Xcode build products and indexes. Rebuilt on next build."),
            ("~/Library/Developer/Xcode/iOS DeviceSupport", .redownload, "Debug symbols for iOS versions. Re-created when a device connects."),
            ("~/Library/Developer/Xcode/watchOS DeviceSupport", .redownload, "Debug symbols for watchOS versions. Re-created when a watch connects."),
            ("~/Library/Developer/Xcode/Archives", .review, "Archived app builds. Keep ones you may need for crash reports."),
            ("~/Library/Developer/CoreSimulator/Caches", .safe, "Simulator caches."),
            ("~/Library/Developer/CoreSimulator/Devices", .review, "Simulator devices and their app data. `xcrun simctl delete unavailable` removes stale ones safely."),
            ("~/Library/Android/sdk", .review, "Android SDK. Needed by Android Studio; remove unused system images in its SDK Manager."),
            ("~/Library/Containers/com.utmapp.UTM", .review, "UTM virtual machines."),

            // --- Home: developer caches
            ("~/.cache", .redownload, "Command-line tool caches (pip, Hugging Face, Playwright…). Tools re-download what they need."),
            ("~/.cache/huggingface", .redownload, "Downloaded AI models. Safe to delete, but each model re-downloads (often GBs) next time it's used."),
            ("~/.cache/huggingface/hub", .redownload, "Downloaded AI models. Safe to delete, but each model re-downloads (often GBs) next time it's used."),
            ("~/.cache/torch", .redownload, "PyTorch model weights. Re-downloaded when needed."),
            ("~/.cache/whisper", .redownload, "Whisper speech models. Re-downloaded when needed."),
            ("~/.cache/pip", .safe, "pip download cache."),
            ("~/.cache/uv", .safe, "uv package cache."),
            ("~/.cache/pypoetry", .safe, "Poetry package cache."),
            ("~/.cache/ms-playwright", .redownload, "Browsers for Playwright. Re-installed with `npx playwright install`."),
            ("~/.cache/puppeteer", .redownload, "Chrome for Puppeteer. Re-downloaded on next install."),
            ("~/.cache/selenium", .redownload, "Browser drivers for Selenium."),
            ("~/.cache/pre-commit", .safe, "pre-commit hook environments."),
            ("~/.cache/node-gyp", .safe, "Node native-build headers."),
            ("~/.cache/yarn", .safe, "Yarn package cache."),
            ("~/.cache/go-build", .safe, "Go build cache."),
            ("~/.cache/lm-studio", .review, "LM Studio data and models. Remove models inside LM Studio instead."),
            ("~/.npm", .safe, "npm cache and logs."),
            ("~/.npm/_cacache", .safe, "npm package cache."),
            ("~/.bun/install/cache", .safe, "Bun package cache."),
            ("~/.gradle/caches", .redownload, "Gradle dependency and build caches."),
            ("~/.gradle/wrapper/dists", .redownload, "Gradle versions. Re-downloaded per project."),
            ("~/.m2/repository", .redownload, "Maven dependencies."),
            ("~/.nuget/packages", .redownload, "NuGet packages."),
            ("~/.cargo/registry", .redownload, "Rust crate downloads."),
            ("~/.rustup", .review, "Rust toolchains. Remove old ones with `rustup toolchain uninstall`."),
            ("~/go/pkg/mod", .redownload, "Go module cache. `go clean -modcache` clears it."),
            ("~/.cocoapods/repos", .redownload, "CocoaPods spec repos."),
            ("~/.platformio/packages", .redownload, "PlatformIO toolchains and frameworks."),
            ("~/.platformio/.cache", .safe, "PlatformIO download cache."),
            ("~/.espressif", .review, "ESP-IDF toolchains. Needed to build ESP32 projects."),
            ("~/.conda/pkgs", .safe, "Conda package cache. `conda clean --all` is the tidy way."),
            ("~/.ollama/models", .review, "Your downloaded Ollama models. Delete with `ollama rm <model>` instead."),
            ("~/.lmstudio/models", .review, "Your LM Studio models. Remove them inside LM Studio."),
            ("~/.diffusionbee", .review, "DiffusionBee models and images."),
            ("~/.keras", .redownload, "Keras datasets and model weights."),
            ("~/.android/avd", .review, "Android emulator images."),
            ("~/.vscode/extensions", .redownload, "VS Code extensions. Reinstalled from the marketplace."),
            ("~/.cursor/extensions", .redownload, "Cursor extensions."),
            ("~/.ssh", .danger, "Your SSH keys."),
            ("~/.gnupg", .danger, "Your encryption keys."),
            ("~/Parallels", .review, "Parallels virtual machines."),
        ]
        var out: [String: Rule] = [:]
        for (p, level, reason) in r {
            let full = p == "~" ? home : (p.hasPrefix("~/") ? home + p.dropFirst(1) : p)
            out[full] = (level, reason)
        }
        return out
    }()

    private static let broadContainers: Set<String> = ["/", "/Users", home]

    /// Folder or file names that mean the same thing wherever they appear.
    private static let nameRules: [String: Rule] = [
        "node_modules": (.redownload, "JavaScript dependencies. `npm install` restores them."),
        ".venv": (.redownload, "Python virtual environment. Recreate it and reinstall requirements."),
        "venv": (.redownload, "Python virtual environment. Recreate it and reinstall requirements."),
        "__pycache__": (.safe, "Compiled Python files. Recreated automatically."),
        ".build": (.safe, "Swift build output. Rebuilt on next build."),
        "DerivedData": (.safe, "Xcode build output. Rebuilt on next build."),
        ".gradle": (.safe, "Per-project Gradle cache. Rebuilt on next build."),
        ".next": (.safe, "Next.js build output. Rebuilt on next build."),
        ".nuxt": (.safe, "Nuxt build output. Rebuilt on next build."),
        ".turbo": (.safe, "Turborepo cache."),
        ".parcel-cache": (.safe, "Parcel bundler cache."),
        ".pio": (.safe, "PlatformIO build output for this project."),
        "Caches": (.safe, "Cache folder. Rebuilt by the app that owns it."),
        ".DS_Store": (.safe, "Finder view settings."),
        ".git": (.danger, "Git history for this project. Deleting loses unpushed work."),
    ]

    private static let extensionRules: [String: Rule] = [
        "dmg": (.review, "Disk image, usually an installer. Safe once the app is installed."),
        "pkg": (.review, "Installer package. Safe once installed."),
        "xip": (.review, "Xcode installer archive. Safe once installed."),
        "ipsw": (.safe, "iOS/macOS firmware download. Re-downloaded if ever needed."),
        "pvm": (.review, "Parallels virtual machine, including everything inside it."),
        "vmwarevm": (.review, "VMware virtual machine, including everything inside it."),
        "utm": (.review, "UTM virtual machine, including everything inside it."),
        "photoslibrary": (.danger, "A Photos library. Manage it in the Photos app."),
        "musiclibrary": (.danger, "A Music library."),
        "app": (.review, "An application. Its settings and data stay in ~/Library."),
        "log": (.safe, "Log file."),
        "crash": (.safe, "Crash report."),
    ]

    static func assess(_ node: FileNode) -> RiskAssessment {
        assess(path: node.url.standardizedFileURL.path)
    }

    static func assess(path: String) -> RiskAssessment {
        var current = path
        var isLeaf = true
        while !current.isEmpty {
            if case let (level, reason)? = pathRules[current] {
                // Very broad containers only describe themselves, not everything inside them.
                if !isLeaf && broadContainers.contains(current) { break }
                return RiskAssessment(level: level, reason: isLeaf ? reason : "Inside: " + reason)
            }
            let name = (current as NSString).lastPathComponent
            if case let (level, reason)? = nameRules[name] {
                return RiskAssessment(level: level, reason: isLeaf ? reason : "Inside: " + reason)
            }
            let ext = (name as NSString).pathExtension.lowercased()
            if !ext.isEmpty, case let (level, reason)? = extensionRules[ext] {
                return RiskAssessment(level: level, reason: isLeaf ? reason : "Inside: " + reason)
            }
            if current == "/" { break }
            current = (current as NSString).deletingLastPathComponent
            isLeaf = false
        }
        return RiskAssessment(level: .unknown, reason: "Deletable doesn't recognise this. Check what it is before deleting.")
    }
}

/// Small coloured risk pill.
struct RiskBadge: View {
    let assessment: RiskAssessment
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: assessment.level.symbol)
            if !compact { Text(assessment.level.title) }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(assessment.level.color)
        .padding(.horizontal, compact ? 0 : 6)
        .padding(.vertical, compact ? 0 : 2)
        .background {
            if !compact { Capsule().fill(assessment.level.color.opacity(0.15)) }
        }
        .help("\(assessment.level.title): \(assessment.reason)")
    }
}
