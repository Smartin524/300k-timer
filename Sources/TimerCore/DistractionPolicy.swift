import Foundation

public enum DistractionPolicy {
    public static func siteName(for address: String) -> String? {
        guard let entry = SiteCatalog.entry(for: address), entry.pausesStudy else { return nil }
        return entry.title
    }
}
