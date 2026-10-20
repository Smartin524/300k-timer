import Foundation

/// One table for both site behaviours: pausing study, and counting junk time.
enum SiteCatalog {
    struct Entry {
        let domain: String
        let title: String
        let pausesStudy: Bool
        let waste: WasteSite?
    }

    static let entries: [Entry] = [
        Entry(domain: "bilibili.com", title: "B 站", pausesStudy: true, waste: .bilibili),
        Entry(domain: "b23.tv", title: "B 站", pausesStudy: true, waste: .bilibili),
        Entry(domain: "xiaohongshu.com", title: "小红书", pausesStudy: true, waste: .xiaohongshu),
        Entry(domain: "xhslink.com", title: "小红书", pausesStudy: true, waste: .xiaohongshu),
        Entry(domain: "tieba.baidu.com", title: "贴吧", pausesStudy: true, waste: .tieba),
        Entry(domain: "tieba.com", title: "贴吧", pausesStudy: true, waste: .tieba),
        Entry(domain: "lol.fandom.com", title: "Leaguepedia", pausesStudy: true, waste: nil),
        Entry(domain: "lol.gamepedia.com", title: "Leaguepedia", pausesStudy: true, waste: nil),
        Entry(domain: "leaguepedia.com", title: "Leaguepedia", pausesStudy: true, waste: nil),
        Entry(domain: "douyu.com", title: "斗鱼", pausesStudy: false, waste: .douyu),
        Entry(domain: "x.com", title: "X", pausesStudy: false, waste: .x),
        Entry(domain: "twitter.com", title: "X", pausesStudy: false, waste: .x)
    ]

    /// Matches the host (or a subdomain) of an http(s) address only, never its path or query.
    static func entry(for address: String) -> Entry? {
        guard let url = URL(string: address),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) else { return nil }
        return entries.first { host == $0.domain || host.hasSuffix("." + $0.domain) }
    }
}
