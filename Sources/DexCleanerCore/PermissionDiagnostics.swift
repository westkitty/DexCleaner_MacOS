import Foundation

public enum PermissionDiagnostics {
    public static func evaluate(home: String = NSHomeDirectory()) -> [PermissionDiagnostic] {
        let protectedSamples = [
            ("Mail access check", "Library/Mail"),
            ("Safari access check", "Library/Safari"),
            ("Messages access check", "Library/Messages")
        ]

        return protectedSamples.map { name, relativePath in
            let url = URL(fileURLWithPath: home).appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return PermissionDiagnostic(
                    title: name,
                    status: "Not testable",
                    detail: "The sample path does not exist in this account, so access cannot be inferred.",
                    remediation: "No conclusion is possible from this sample. Review scan completeness instead."
                )
            }
            do {
                _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants])
                return PermissionDiagnostic(
                    title: name,
                    status: "Access available",
                    detail: "DexCleaner successfully listed this protected sample folder in the current execution context.",
                    remediation: "No action is required for this sample. This does not prove access to every protected location."
                )
            } catch {
                return PermissionDiagnostic(
                    title: name,
                    status: "Access limited",
                    detail: "The folder exists but could not be listed: \(error.localizedDescription)",
                    remediation: "Grant Full Disk Access only when a more complete audit is needed, then run a new scan."
                )
            }
        }
    }

    public static func summary(_ diagnostics: [PermissionDiagnostic]) -> String {
        if diagnostics.contains(where: { $0.status == "Access limited" }) {
            return "Limited access detected"
        }
        if diagnostics.contains(where: { $0.status == "Access available" }) {
            return "Some protected samples readable"
        }
        return "Access not testable"
    }
}
