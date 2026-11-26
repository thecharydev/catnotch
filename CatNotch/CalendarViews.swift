import SwiftUI
import CatNotchCore

private func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

private func firstOfMonth(_ date: Date) -> Date {
    Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date))!
}

/// "All day" for an event that fills the day (or the day is inside a longer one), else "start to end".
private func timeText(_ event: AgendaEvent, on day: Date) -> String {
    if event.allDay || (event.start <= day && event.end >= Agenda.dayStart(day, offset: 1)) { return "All day" }
    return "\(time(event.start)) to \(time(event.end))"
}

/// A centred message with an optional button, for the states where there is nothing to list.
private struct Message: View {
    @Environment(\.companionAccent) private var accent
    let text: String
    var note: String?
    /// Where the reading comes from; adds an info icon that opens the whole list in place of the note.
    var source: DataSource?
    var action: String?
    var onAction: () -> Void = {}
    @State private var showSource = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(text).font(.system(size: 13, weight: .semibold))
                if let source { SourceInfo(source: source, open: $showSource) }
            }
            if let source, showSource { SourceLines(source: source, size: 11) }
            else if let note { Text(note).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).multilineTextAlignment(.center) }
            if let action {
                Button(action: onAction) {
                    Text(action).font(.system(size: 11, weight: .semibold)).foregroundStyle(.black)
                        .padding(.horizontal, 12).padding(.vertical, 5).background(Capsule().fill(accent))
                }
                .buttonStyle(.lively).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }
}

/// One event: dot, title, time, "Now" and Join. Birthdays and holidays swap the dot for an icon and show no time.
private struct EventRow: View {
    @Environment(\.companionAccent) private var accent
    let event: AgendaEvent
    let day: Date
    let now: Date
    var grey = false
    var agenda: AgendaModel
    @State private var hovering = false

    var body: some View {
        let special = event.kind != .event
        let color = Color(hex: event.color)
        HStack(spacing: 8) {
            Button { agenda.open(event) } label: {
                HStack(spacing: 8) {
                    if special {
                        Image(systemName: event.kind == .birthday ? "birthday.cake.fill" : "flag.fill").font(.system(size: 10)).foregroundStyle(color)
                    } else {
                        Circle().fill(color).frame(width: 8, height: 8)
                    }
                    Text(event.displayTitle).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 4)
                    if !special { Text(timeText(event, on: day)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1) }
                    if !special && event.start <= now && now < event.end {
                        Text("NOW").font(.system(size: 9, weight: .bold)).foregroundStyle(.black).padding(.horizontal, 5).background(Capsule().fill(accent))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).pointerCursor()
            if event.joinURL != nil && !grey && !special {
                Button { agenda.join(event) } label: {
                    Label("Join", systemImage: "video.fill").font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(.white.opacity(0.14)))
                }
                .buttonStyle(.lively).accessibilityLabel("Join \(event.displayTitle)")
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(hovering ? 0.08 : 0)))
        .opacity(grey ? 0.4 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }
}

/// Today and Tomorrow, what is still to come, with a line for each day that has nothing.
private struct Upcoming: View {
    @Environment(\.companionAccent) private var accent
    let events: [AgendaEvent]
    let now: Date
    var agenda: AgendaModel

    var body: some View {
        let days = [0, 1].map { offset in
            let day = Agenda.dayStart(now, offset: offset)
            return (label: offset == 0 ? "Today" : "Tomorrow", day: day, list: Agenda.events(on: day, in: events))
        }
        if days.allSatisfy(\.list.isEmpty) {
            Message(text: "Nothing planned")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(days, id: \.label) { d in
                        Text(d.label.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(accent)
                        if d.list.isEmpty { Text(d.label == "Today" ? "Nothing planned today" : "Nothing planned").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)) }
                        ForEach(d.list, id: \.key) { EventRow(event: $0, day: d.day, now: now, agenda: agenda) }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

/// One day: its heading and counts, the special days, the events, and its tasks with a line to add one.
private struct DayPane: View {
    let day: Date
    let now: Date
    let events: [AgendaEvent]
    let granted: Bool
    var agenda: AgendaModel
    var tasks: TaskModel
    @State private var draft = ""

    var body: some View {
        let list = Agenda.events(on: day, in: events)
        let special = list.filter { $0.kind != .event }
        let normal = list.filter { $0.kind == .event }
        let mine = tasks.dayTasks(on: day, now: now)
        VStack(alignment: .leading, spacing: 2) {
            Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.system(size: 12, weight: .semibold))
            Text(Agenda.countLine(special: granted ? special.count : nil, events: granted ? normal.count : nil, tasks: mine.count))
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !granted { Text("Calendar access is off").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).padding(.vertical, 4) }
                    if !special.isEmpty {
                        Text("SPECIAL DAYS").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(.white.opacity(0.4)).padding(.horizontal, 6).padding(.top, 4)
                        ForEach(special, id: \.key) { EventRow(event: $0, day: day, now: now, agenda: agenda) }
                    }
                    ForEach(normal, id: \.key) { EventRow(event: $0, day: day, now: now, grey: $0.end <= now, agenda: agenda) } // ended ones stay, greyed
                    ForEach(mine, id: \.id) { TaskRow(task: $0, tasks: tasks) }
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
                        TextField("Add a task", text: $draft).textFieldStyle(.plain).font(.system(size: 12))
                            .onSubmit { tasks.add(draft, due: day); draft = "" }
                    }
                    .padding(.horizontal, 6).padding(.vertical, 5)
                }
            }
            .scrollIndicators(.never)
        }
    }
}

/// The shown month as a grid: today filled, the chosen day ringed, a dot under a day that has something.
private struct MonthGrid: View {
    @Environment(\.companionAccent) private var accent
    @Binding var month: Date
    @Binding var selected: Date?
    let now: Date
    let busy: (Date) -> Bool

    private let columns = Array(repeating: GridItem(.fixed(24), spacing: 0), count: 7)

    private func go(_ by: Int) { month = Calendar.current.date(byAdding: .month, value: by, to: month)! }

    var body: some View {
        let cal = Calendar.current
        let atNow = cal.isDate(month, equalTo: now, toGranularity: .month)
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(month.formatted(.dateTime.month(.wide))).font(.system(size: 12, weight: .semibold))
                    + Text(" " + month.formatted(.dateTime.year(.defaultDigits))).font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                Spacer(minLength: 0)
                if !atNow || (selected.map { !cal.isDate($0, inSameDayAs: now) } ?? false) { // not when today itself is the chosen day
                    Button { month = firstOfMonth(now); selected = nil } label: {
                        Text("TODAY").font(.system(size: 9, weight: .bold)).foregroundStyle(.black).padding(.horizontal, 6).background(Capsule().fill(accent))
                    }
                    .buttonStyle(.lively)
                }
                Button { go(-1) } label: { Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold)).frame(width: 16, height: 16).contentShape(Rectangle()) }
                    .buttonStyle(.lively).accessibilityLabel("Previous month")
                Button { go(1) } label: { Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).frame(width: 16, height: 16).contentShape(Rectangle()) }
                    .buttonStyle(.lively).accessibilityLabel("Next month")
            }
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array("SMTWTFS".enumerated()), id: \.offset) { Text(String($0.element)).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.4)) }
                ForEach(Array(Agenda.monthCells(month).enumerated()), id: \.offset) { _, d in
                    if d == 0 {
                        Color.clear.frame(height: 22)
                    } else {
                        let day = cal.date(byAdding: .day, value: d - 1, to: month)!
                        let today = cal.isDate(day, inSameDayAs: now)
                        let chosen = selected.map { cal.isDate(day, inSameDayAs: $0) } ?? false
                        Button { selected = chosen ? nil : day } label: {
                            ZStack {
                                if today { Circle().fill(accent) }
                                if chosen { Circle().stroke(accent, lineWidth: 1.5) }
                                Text("\(d)").font(.system(size: 10, weight: today ? .bold : .regular)).foregroundStyle(today ? .black : .white.opacity(0.8))
                                if busy(day) { Circle().fill(today ? .black : accent).frame(width: 3, height: 3).offset(y: 8) }
                            }
                            .frame(width: 22, height: 22).contentShape(Circle())
                        }
                        .buttonStyle(.lively)
                        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    }
                }
            }
        }
    }
}

/// The Calendar view: the month on the left; on the right Today and Tomorrow, or the chosen day.
struct CalendarPage: View {
    var agenda: AgendaModel
    var tasks: TaskModel
    @Binding var month: Date
    @Binding var selected: Date?

    var body: some View {
        TimelineView(.everyMinute) { context in // ended events and the Now mark come from the clock, with no new read
            let now = context.date
            let granted = agenda.eventsAccess == .granted
            let visible = granted ? Agenda.visible(agenda.events, hidden: agenda.hidden) : []
            HStack(alignment: .top, spacing: 12) { // top, not centred: the month is a few points shorter than the page, and centring it left a gap under the bar
                MonthGrid(month: $month, selected: $selected, now: now) { day in
                    visible.contains { Agenda.overlaps($0, day: day) } || tasks.hasOpenTask(on: day)
                }
                .frame(width: 168)
                Rectangle().fill(.white.opacity(0.1)).frame(width: 1)
                Group {
                    if let selected {
                        DayPane(day: selected, now: now, events: visible, granted: granted, agenda: agenda, tasks: tasks)
                    } else {
                        switch agenda.eventsAccess {
                        case .unknown:
                            Message(text: "Show your calendar here", note: "CatNotch reads the events in your Mac's Calendar app to show what is next. It stays on your Mac and never changes anything.", source: .calendar,
                                    action: "Allow", onAction: agenda.allowCalendar)
                        case .denied:
                            Message(text: "Calendar access is off", action: "Open System Settings") { agenda.openPrivacy(reminders: false) }
                        case .granted:
                            Upcoming(events: Agenda.upcoming(visible, now: now), now: now, agenda: agenda)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // Its own size, as Focus and Files have: the page does not depend on what the Notch hands it.
        .frame(width: NotchLayout.calendarContent(weeks: Agenda.weeks(month)).width, height: NotchLayout.calendarContent(weeks: Agenda.weeks(month)).height, alignment: .top)
        .onChange(of: selected) { // a key moved the day into another month: the grid follows
            if let day = selected, !Calendar.current.isDate(day, equalTo: month, toGranularity: .month) { month = firstOfMonth(day) }
        }
        .task { // the permission may have changed in System Settings
            // The read is synchronous EventKit work on the main thread: made on appear it stalled the open spring (the Notch dropped, froze, then jumped). Wait for the spring to settle.
            try? await Task.sleep(for: .milliseconds(800))
            agenda.refreshAccess()
        }
        .task(id: month) { // reads the month being shown; selecting a day outside it clears the pick
            agenda.showMonth(month)
            if let day = selected, !Calendar.current.isDate(day, equalTo: month, toGranularity: .month) { selected = nil }
        }
    }
}

/// Apple Reminders that are not done and have a due day: overdue, today, later. Read only.
struct RemindersPage: View {
    @Environment(\.companionAccent) private var accent
    var agenda: AgendaModel

    var body: some View {
        switch agenda.remindersAccess {
        case .unknown:
            Message(text: "Show your reminders here", note: "CatNotch reads the reminders in your Mac's Reminders app to show what is due. It stays on your Mac and never changes anything.", source: .reminders,
                    action: "Allow", onAction: agenda.allowReminders)
        case .denied:
            Message(text: "Reminders access is off", action: "Open System Settings") { agenda.openPrivacy(reminders: true) }
        case .granted:
            TimelineView(.everyMinute) { context in
                let groups = Reminders.grouped(agenda.reminders, now: context.date)
                if groups.isEmpty {
                    Message(text: "Nothing due")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(groups, id: \.group) { g in
                                Text(g.group.title.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.2)
                                    .foregroundStyle(g.group == .overdue ? .red.opacity(0.85) : accent)
                                ForEach(g.items) { item in
                                    ReminderHover { Button { agenda.openReminder(item) } label: {
                                        HStack(spacing: 8) {
                                            Circle().stroke(Color(hex: item.color), lineWidth: 1.5).frame(width: 11, height: 11)
                                            Text(item.title.isEmpty ? "Untitled" : item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                            Spacer(minLength: 4)
                                            Text(when(item, group: g.group)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                                        }
                                        .padding(.horizontal, 6).padding(.vertical, 3).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain).pointerCursor() }
                                }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    /// Today shows the time, any other day shows the date and the time.
    private func when(_ item: ReminderItem, group: ReminderGroup) -> String {
        let day = item.due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        switch (group, item.hasTime) {
        case (.today, true): return time(item.due)
        case (.today, false): return "Today"
        case (_, true): return "\(day), \(time(item.due))"
        default: return day
        }
    }
}

/// Home's next event: its title, how long until it starts and, when there is one, the Join button. Hidden when there is nothing left today.
struct NextEventCard: View {
    var agenda: AgendaModel

    var body: some View {
        if agenda.eventsAccess == .granted && agenda.showCalendar {
            TimelineView(.everyMinute) { context in
                let visible = Agenda.visible(agenda.events, hidden: agenda.hidden).filter { $0.kind == .event } // a birthday never reads as next
                if let next = Agenda.nextToday(visible, now: context.date) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NEXT · \(Agenda.until(next, now: context.date).uppercased())").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.white.opacity(0.55))
                        Text(next.displayTitle).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                        Text("\(time(next.start)) to \(time(next.end))").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                        if next.joinURL != nil {
                            Button { agenda.join(next) } label: {
                                Label("Join", systemImage: "video.fill").font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(.white.opacity(0.14)))
                            }
                            .buttonStyle(.lively).padding(.top, 2)
                        }
                    }
                    .padding(14).frame(width: 230, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: next.color).opacity(0.25)))
                    .contentShape(RoundedRectangle(cornerRadius: 18))
                    .onTapGesture { agenda.open(next) }
                    .pointerCursor()
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// A row's pointer highlight, the way an event row lights up.
private struct ReminderHover<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        content
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(hovering ? 0.08 : 0)))
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }
}
