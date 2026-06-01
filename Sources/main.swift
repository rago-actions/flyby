import AppKit
import Foundation

// MARK: - Calendar Polling

struct CalendarEvent {
    let title: String
    let startTime: Date
}

class CalendarPoller {
    private var timer: Timer?
    private var notifiedEvents: Set<String> = []
    private let onMeetingSoon: (CalendarEvent) -> Void

    init(onMeetingSoon: @escaping (CalendarEvent) -> Void) {
        self.onMeetingSoon = onMeetingSoon
    }

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        fetchUpcomingEvents { [weak self] events in
            guard let self = self else { return }
            let now = Date()
            let fiveMinutes: TimeInterval = 5 * 60

            let timestamp = ISO8601DateFormatter().string(from: now)
            if events.isEmpty {
                print("[\(timestamp)] Poll: no upcoming events")
            } else {
                for e in events {
                    let mins = e.startTime.timeIntervalSince(now) / 60
                    print("[\(timestamp)] Poll: \"\(e.title)\" in \(String(format: "%.1f", mins)) min")
                }
            }

            for event in events {
                let timeUntil = event.startTime.timeIntervalSince(now)
                let eventKey = "\(event.title)-\(Int(event.startTime.timeIntervalSince1970))"

                if timeUntil > 0 && timeUntil <= fiveMinutes && !self.notifiedEvents.contains(eventKey) {
                    self.notifiedEvents.insert(eventKey)
                    DispatchQueue.main.async {
                        self.onMeetingSoon(event)
                    }
                }
            }

            // Cleanup old entries
            self.notifiedEvents = self.notifiedEvents.filter { key in
                events.contains { "\($0.title)-\(Int($0.startTime.timeIntervalSince1970))" == key }
            }
        }
    }

    private func fetchUpcomingEvents(completion: @escaping ([CalendarEvent]) -> Void) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/Users/rgodishela/.local/bin/claude")

        let now = ISO8601DateFormatter().string(from: Date())

        let prompt = """
        Use the calendar_events tool to get my events for today. \
        Return ONLY a JSON array of objects with "title" and "start" (ISO8601) fields. \
        Only include events starting within the next 10 minutes from now (\(now)). \
        No explanation, just the JSON array. If no events, return [].
        """

        task.arguments = ["-p", prompt, "--output-format", "json"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let raw = String(data: data, encoding: .utf8) else {
                print("[Poll error] Could not decode CLI output as UTF-8")
                completion([])
                return
            }

            print("[Poll raw] exit=\(task.terminationStatus) bytes=\(data.count)")
            if data.count < 500 {
                print("[Poll raw] \(raw)")
            }

            // Parse the claude JSON envelope
            if let envelopeData = raw.data(using: .utf8),
               let envelope = try? JSONSerialization.jsonObject(with: envelopeData) as? [String: Any],
               let result = envelope["result"] as? String {
                let events = parseEvents(from: result)
                completion(events)
            } else {
                let events = parseEvents(from: raw)
                completion(events)
            }
        } catch {
            print("[Poll error] Failed to launch claude CLI: \(error)")
            completion([])
        }
    }

    private func parseEvents(from text: String) -> [CalendarEvent] {
        // Find JSON array in the text
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]") else { return [] }

        let jsonStr = String(text[start...end])
        guard let data = jsonStr.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackFormatter = ISO8601DateFormatter()

        return arr.compactMap { item in
            guard let title = item["title"] as? String,
                  let startStr = item["start"] as? String else { return nil }
            guard let date = formatter.date(from: startStr) ?? fallbackFormatter.date(from: startStr) else { return nil }
            return CalendarEvent(title: title, startTime: date)
        }
    }
}

// MARK: - Airplane Animation Window

class AirplaneWindow: NSWindow {
    private var animTimer: Timer?
    private var airplaneLabel: NSTextField!
    private var bannerLabel: NSTextField!
    private var startTime: Date?
    private let flightDuration: TimeInterval = 15.0

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.frame

        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.level = NSWindow.Level(Int(CGShieldingWindowLevel()))
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    func flyAcross(meetingTitle: String) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.frame

        let container = NSView(frame: screenFrame)
        self.contentView = container

        // Airplane emoji label
        airplaneLabel = NSTextField(labelWithString: "✈️")
        airplaneLabel.font = NSFont.systemFont(ofSize: 48)
        airplaneLabel.isBezeled = false
        airplaneLabel.drawsBackground = false
        airplaneLabel.isEditable = false
        airplaneLabel.sizeToFit()
        airplaneLabel.frame.origin = CGPoint(x: -80, y: screenFrame.height * 0.6)
        container.addSubview(airplaneLabel)

        // Banner label
        bannerLabel = NSTextField(labelWithString: "  \(meetingTitle) — in 5 min  ")
        bannerLabel.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        bannerLabel.textColor = .white
        bannerLabel.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 0.9)
        bannerLabel.drawsBackground = true
        bannerLabel.isBezeled = false
        bannerLabel.isEditable = false
        bannerLabel.wantsLayer = true
        bannerLabel.layer?.cornerRadius = 10
        bannerLabel.layer?.masksToBounds = true
        bannerLabel.sizeToFit()
        let bannerHeight: CGFloat = 30
        bannerLabel.frame.size.height = bannerHeight
        bannerLabel.frame.size.width += 20
        bannerLabel.frame.origin = CGPoint(x: -bannerLabel.frame.width - 100, y: screenFrame.height * 0.6 + 12)
        container.addSubview(bannerLabel)

        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Start frame-by-frame animation
        startTime = Date()
        animTimer?.invalidate()
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let startTime = startTime else { return }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenWidth = screen.frame.width
        let elapsed = Date().timeIntervalSince(startTime)
        let progress = min(elapsed / flightDuration, 1.0)

        // Ease in-out
        let eased = progress < 0.5
            ? 2 * progress * progress
            : 1 - pow(-2 * progress + 2, 2) / 2

        let startX: CGFloat = -80
        let endX = screenWidth + 100
        let x = startX + (endX - startX) * eased

        // Vertical wave
        let baseY = screen.frame.height * 0.6
        let wave = sin(progress * .pi * 3) * 20
        let y = baseY + wave

        airplaneLabel.frame.origin = CGPoint(x: x, y: y)
        bannerLabel.frame.origin = CGPoint(x: x - bannerLabel.frame.width - 10, y: y + 12)

        if progress >= 1.0 {
            animTimer?.invalidate()
            animTimer = nil
            self.startTime = nil
            self.orderOut(nil)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var poller: CalendarPoller!
    var airplaneWindow: AirplaneWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menubar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "✈️"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "FlyBy — Meeting Reminder", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let testItem = NSMenuItem(title: "Test Flight", action: #selector(testFlight), keyEquivalent: "t")
        testItem.target = self
        menu.addItem(testItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        airplaneWindow = AirplaneWindow()

        // Start polling
        poller = CalendarPoller { [weak self] event in
            self?.triggerFlyBy(for: event)
        }
        poller.start()

        // One-shot test if launched with --test flag
        if CommandLine.arguments.contains("--test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.testFlight()
            }
        }

        print("✈️ FlyBy is active — watching your calendar.")
    }

    func triggerFlyBy(for event: CalendarEvent) {
        airplaneWindow.flyAcross(meetingTitle: event.title)
    }

    @objc func testFlight() {
        let testEvent = CalendarEvent(title: "Team Standup", startTime: Date().addingTimeInterval(300))
        triggerFlyBy(for: testEvent)
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
