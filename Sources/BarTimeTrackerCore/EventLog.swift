import Foundation

public final class EventLog {
    public let fileURL: URL

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let header = "date,time,event_type,event_source,project_name\n"
            try? header.data(using: .utf8)?.write(to: fileURL, options: .atomic)
        }
    }

    public func append(at date: Date = Date(), eventType: String, eventSource: String, projectName: String) {
        let row = "\(Self.dateFmt.string(from: date)),\(Self.timeFmt.string(from: date)),\(eventType),\(csv(eventSource)),\(csv(projectName))\n"
        guard let data = row.data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { handle.closeFile() }
        handle.seekToEndOfFile()
        handle.write(data)
    }

    private func csv(_ s: String) -> String {
        guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
        return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
