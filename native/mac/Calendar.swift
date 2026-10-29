// Calendar: reads the Mac's calendars through EventKit. Read only by design
// (docs/specs/0003-notch-calendar-agenda.md): this file only ever asks for
// and reads events, and never calls a write API of EventKit.
import AppKit
import EventKit

private let eventStore = EKEventStore()
private var changeObserver: NSObjectProtocol?
private var changePending = false

func calendarAccess() -> String {
    let status = EKEventStore.authorizationStatus(for: .event)
    if status == .notDetermined { return "unknown" }
    if #available(macOS 14, *) { return status == .fullAccess ? "granted" : "denied" }
    return status == .authorized ? "granted" : "denied"
}

private func hex(_ color: CGColor) -> String {
    guard let c = NSColor(cgColor: color)?.usingColorSpace(.sRGB) else { return "#888888" }
    return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
}

private func allowed(_ host: String) -> Bool {
    host == "zoom.us" || host.hasSuffix(".zoom.us") || host == "meet.google.com" || host == "teams.microsoft.com" || host == "teams.live.com"
}

private let linkPattern = try? NSRegularExpression(pattern: "https://[^\\s<>\"')\\]]+")

/// The first allowlisted https link in the event's url, then location, then notes.
private func joinLink(_ event: EKEvent) -> String? {
    for text in [event.url?.absoluteString, event.location, event.notes] {
        guard let text = text, let linkPattern = linkPattern else { continue }
        let range = NSRange(text.startIndex..., in: text)
        for match in linkPattern.matches(in: text, range: range) {
            guard let r = Range(match.range, in: text) else { continue }
            let link = String(text[r])
            if let host = URL(string: link)?.host?.lowercased(), allowed(host) { return link }
        }
    }
    return nil
}

private func declined(_ event: EKEvent) -> Bool {
    event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus == .declined
}

private let iso = ISO8601DateFormatter()
private let isoMs: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
/// JS sends "...000Z" (with milliseconds); the plain formatter rejects that.
private func parseDate(_ s: String) -> Date? { isoMs.date(from: s) ?? iso.date(from: s) }

func handleCalendar(_ cmd: String, _ id: Any, _ args: [String: Any]) {
    let granted = calendarAccess() == "granted"
    switch cmd {
    case "calendarStatus":
        emit(["id": id, "status": calendarAccess()])
    case "calendarRequest":
        if calendarAccess() != "unknown" { return emit(["id": id, "status": calendarAccess()]) }
        // A background helper has no window to anchor the system prompt to; come forward so it shows.
        NSApp.activate(ignoringOtherApps: true)
        let done: (Bool, Error?) -> Void = { _, _ in
            DispatchQueue.main.async { emit(["id": id, "status": calendarAccess()]) }
        }
        if #available(macOS 14, *) { eventStore.requestFullAccessToEvents(completion: done) }
        else { eventStore.requestAccess(to: .event, completion: done) }
    case "calendarList":
        let list = granted ? eventStore.calendars(for: .event) : []
        emit(["id": id, "calendars": list.map {
            ["id": $0.calendarIdentifier, "title": $0.title, "color": hex($0.cgColor), "account": $0.source?.title ?? ""]
        }])
    case "calendarEvents":
        guard granted, let from = (args["from"] as? String).flatMap(parseDate), let to = (args["to"] as? String).flatMap(parseDate) else {
            return emit(["id": id, "status": calendarAccess(), "events": []])
        }
        let found = eventStore.events(matching: eventStore.predicateForEvents(withStart: from, end: to, calendars: nil))
        let events: [[String: Any]] = found.filter { $0.status != .canceled && !declined($0) }.map {
            [
                "id": $0.eventIdentifier ?? "",
                "title": $0.title ?? "",
                "start": iso.string(from: $0.startDate),
                "end": iso.string(from: $0.endDate),
                "allDay": $0.isAllDay,
                "calendarId": $0.calendar.calendarIdentifier,
                "calendarColor": hex($0.calendar.cgColor),
                "calendarType": $0.calendar.type == .birthday ? "birthday" : !$0.calendar.allowsContentModifications ? "readonly" : "other",
                "joinUrl": joinLink($0) as Any? ?? NSNull(),
            ]
        }
        emit(["id": id, "status": "granted", "events": events])
    default: break
    }
}

/// Tells main when the Calendar app changes, so the view asks again.
func watchCalendar(_ on: Bool) {
    if let observer = changeObserver { NotificationCenter.default.removeObserver(observer) }
    changeObserver = nil
    guard on else { return }
    changeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { _ in
        if changePending { return }
        changePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            changePending = false
            emit(["t": "calendarChanged"])
        }
    }
}
