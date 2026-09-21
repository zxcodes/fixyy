import AppKit

public struct PasteboardSnapshot: Sendable {
    private let items: [[String: Data]]

    public init(pasteboard: NSPasteboard = .general) {
        var captured: [[String: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var map: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    map[type.rawValue] = data
                }
            }
            captured.append(map)
        }
        self.items = captured
    }

    public func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        var objects: [NSPasteboardItem] = []
        for map in items {
            let item = NSPasteboardItem()
            for (raw, data) in map {
                item.setData(data, forType: NSPasteboard.PasteboardType(raw))
            }
            objects.append(item)
        }
        if !objects.isEmpty {
            pasteboard.writeObjects(objects)
        }
    }
}
