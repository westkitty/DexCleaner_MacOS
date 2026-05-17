import Foundation

public enum PermissionDiagnostics {
    public static func evaluate(home: String = NSHomeDirectory()) -> [PermissionDiagnostic] {
        let protectedSamples = [
            ("Mail", "Library/Mail"),
            ("Safari", "Library/Safari"),
            ("Messages", "Library/Messages")
        ]

        return protectedSamples.map { name, relativePath in
            let url = URL(fileURLWithPath: home).appendingPathComponent(relativePath)
            let exists = FileManager.default.fileExists(atPath: url.path)
            let readable = FileManager.default.isReadableFile(atPath: url.path)
            if exists && !readable {
                return PermissionDiagnostic(
                    title: name,
                    status: "Limited access",
                    detail: "DexCleaner could see the folder but could not read it.",
                    remediation: "Grant Full Disk Access to inspect protected macOS data. Cleanup remains exact allowlist only."
                )
            }
            if exists && readable {
                return PermissionDiagnostic(
                    title: name,
                    status: "Readable",
                    detail: "Sample protected folder is readable in this execution context.",
                    remediation: "No action needed for this sample."
                )
            }
            return PermissionDiagnostic(
                title: name,
                status: "Not present or hidden",
                detail: "Sample path was not present or was hidden by macOS privacy controls.",
                remediation: "If scans look incomplete, grant Full Disk Access and rerun."
            )
        }
    }

    public static func summary(_ diagnostics: [PermissionDiagnostic]) -> String {
        if diagnostics.contains(where: { $0.status == "Limited access" }) {
            return "Likely limited; Full Disk Access may be needed for complete audit results."
        }
        if diagnostics.contains(where: { $0.status == "Readable" }) {
            return "Some protected sample folders are readable."
        }
        return "Unknown; no protected sample folder could be confirmed readable."
    }
}
