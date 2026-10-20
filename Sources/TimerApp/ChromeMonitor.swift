import AppKit

/// Read one foreground tab on a serial worker; never retain or log browsing URLs.
/// Sends a single Apple Event (thread-safe) instead of NSAppleScript, which is main-thread only.
@MainActor
final class ChromeMonitor {
    private let queue = DispatchQueue(label: "com.smartin.300ktimer.chrome", qos: .utility)
    private var inFlight = false
    /// The newest request made while a read was running; it runs as soon as that read ends,
    /// so switching back to Chrome is not delayed until the next poll.
    private var queued: ((String?, Int?) -> Void)?

    func inspect(completion: @escaping (String?, Int?) -> Void) {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.google.Chrome" else { return }
        guard !inFlight else {
            queued = completion
            return
        }
        inFlight = true
        queue.async {
            let (address, code) = Self.activeTabURL()
            DispatchQueue.main.async {
                self.inFlight = false
                completion(address, code)
                if let next = self.queued {
                    self.queued = nil
                    self.inspect(completion: next)
                }
            }
        }
    }

    /// `get URL of active tab of window 1` of Google Chrome.
    nonisolated private static func activeTabURL() -> (String?, Int?) {
        let window = specifier(want: "cwin", form: "indx", data: NSAppleEventDescriptor(int32: 1),
                               from: NSAppleEventDescriptor.null())
        let tab = specifier(want: "prop", form: "prop", data: NSAppleEventDescriptor(typeCode: fourCharCode("acTa")), from: window)
        let url = specifier(want: "prop", form: "prop", data: NSAppleEventDescriptor(typeCode: fourCharCode("URL ")), from: tab)
        let event = NSAppleEventDescriptor(eventClass: fourCharCode("core"), eventID: fourCharCode("getd"),
                                           targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: "com.google.Chrome"),
                                           returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(url, forKeyword: keyDirectObject)
        do {
            let reply = try event.sendEvent(options: [.waitForReply], timeout: 3)
            if let error = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value, error != 0 {
                return noWindow(Int(error)) ? ("", nil) : (nil, Int(error))
            }
            return (reply.paramDescriptor(forKeyword: keyDirectObject)?.stringValue ?? "", nil)
        } catch {
            let code = (error as NSError).code
            return noWindow(code) ? ("", nil) : (nil, code)
        }
    }

    /// errAENoSuchObject: Chrome has no window, which is not a detection failure.
    nonisolated private static func noWindow(_ code: Int) -> Bool { code == -1728 }

    nonisolated private static func specifier(want: String, form: String, data: NSAppleEventDescriptor,
                                              from container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: fourCharCode(want)), forKeyword: fourCharCode("want"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: fourCharCode(form)), forKeyword: fourCharCode("form"))
        record.setDescriptor(data, forKeyword: fourCharCode("seld"))
        record.setDescriptor(container, forKeyword: fourCharCode("from"))
        return record.coerce(toDescriptorType: fourCharCode("obj "))!
    }

    nonisolated private static func fourCharCode(_ string: String) -> FourCharCode {
        string.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
    }
}
