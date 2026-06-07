import Foundation

public enum EventLogParser {

    public static func parse(
        csv: String,
        timeZone: TimeZone = .current
    ) -> (screenEvents: [ScreenEvent], projectEntries: [ProjectEntry]) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fmt.timeZone = timeZone

        var screenEvents: [ScreenEvent] = []
        var projectEntries: [ProjectEntry] = []

        for line in csv.components(separatedBy: .newlines).dropFirst() {
            let fields = parseFields(line)
            guard fields.count >= 5,
                  let date = fmt.date(from: "\(fields[0]) \(fields[1])") else { continue }
            switch fields[2] {
            case "on":            screenEvents.append(ScreenEvent(kind: .on, time: date))
            case "off":           screenEvents.append(ScreenEvent(kind: .off, time: date))
            case "screensaverOn": screenEvents.append(ScreenEvent(kind: .screensaverOn, time: date))
            case "screensaverOff":screenEvents.append(ScreenEvent(kind: .screensaverOff, time: date))
            case "entry":         projectEntries.append(ProjectEntry(project: fields[4], time: date))
            default: break
            }
        }

        screenEvents.sort { $0.time < $1.time }
        projectEntries.sort { $0.time < $1.time }
        return (screenEvents, projectEntries)
    }

    private static func parseFields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if inQuotes {
                if c == "\"" {
                    let next = line.index(after: i)
                    if next < line.endIndex && line[next] == "\"" {
                        current.append("\"")
                        i = line.index(after: next)
                        continue
                    }
                    inQuotes = false
                } else {
                    current.append(c)
                }
            } else {
                if c == "\"" { inQuotes = true }
                else if c == "," { fields.append(current); current = "" }
                else { current.append(c) }
            }
            i = line.index(after: i)
        }
        fields.append(current)
        return fields
    }
}
