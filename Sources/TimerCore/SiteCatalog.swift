import Foundation

/// Distracting sites: every one pauses study and counts as 摸鱼 time.
enum SiteCatalog {
    static let domains: [(domain: String, site: WasteSite)] = [
        ("bilibili.com", .bilibili), ("b23.tv", .bilibili),
        ("xiaohongshu.com", .xiaohongshu), ("xhslink.com", .xiaohongshu),
        ("tieba.baidu.com", .tieba), ("tieba.com", .tieba),
        ("douyu.com", .douyu),
        ("x.com", .x), ("twitter.com", .x),
        ("lol.fandom.com", .leaguepedia), ("lol.gamepedia.com", .leaguepedia), ("leaguepedia.com", .leaguepedia)
    ]

    /// Matches the host (or a subdomain) of an http(s) address only, never its path or query.
    static func site(for address: String) -> WasteSite? {
        guard let url = URL(string: address),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) else { return nil }
        return domains.first { host == $0.domain || host.hasSuffix("." + $0.domain) }?.site
    }
}
