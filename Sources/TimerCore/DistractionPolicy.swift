import Foundation

public enum DistractionPolicy {
    public static func siteName(for address: String) -> String? {
        SiteCatalog.site(for: address)?.title
    }
}
