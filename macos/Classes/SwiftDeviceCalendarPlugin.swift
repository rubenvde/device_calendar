import EventKit
import FlutterMacOS
import Foundation
import AppKit

// MARK: - Extensions

extension Date {
    var millisecondsSinceEpoch: Double { return self.timeIntervalSince1970 * 1000.0 }
    
    func convert(from initTimeZone: TimeZone, to targetTimeZone: TimeZone) -> Date {
        let delta = TimeInterval(initTimeZone.secondsFromGMT() - targetTimeZone.secondsFromGMT())
        return self.addingTimeInterval(delta)
    }
}

extension EKParticipant {
    var emailAddress: String? {
        return self.value(forKey: "emailAddress") as? String
    }
}

extension String {
    func match(_ regex: String) -> [[String]] {
        let nsString = self as NSString
        return (try? NSRegularExpression(pattern: regex, options: []))?
            .matches(in: self, options: [], range: NSMakeRange(0, nsString.length))
            .map { match in
                (0..<match.numberOfRanges).map {
                    match.range(at: $0).location == NSNotFound ? "" : nsString.substring(with: match.range(at: $0))
                }
            } ?? []
    }
}

extension NSColor {
    /// Returns the color as an integer (ARGB)
    func rgb() -> Int? {
        let iRed = Int(self.redComponent * 255.0)
        let iGreen = Int(self.greenComponent * 255.0)
        let iBlue = Int(self.blueComponent * 255.0)
        let iAlpha = Int(self.alphaComponent * 255.0)
        return (iAlpha << 24) + (iRed << 16) + (iGreen << 8) + iBlue
    }
    
    /// Initialize NSColor from a hex string (e.g., "0xFF0000FF" for opaque red)
    convenience init?(hex: String) {
        if hex.hasPrefix("0x") {
            let start = hex.index(hex.startIndex, offsetBy: 2)
            let hexColor = String(hex[start...])
            if hexColor.count == 8 {
                let scanner = Scanner(string: hexColor)
                var hexNumber: UInt64 = 0
                if scanner.scanHexInt64(&hexNumber) {
                    let a = CGFloat((hexNumber & 0xff000000) >> 24) / 255.0
                    let r = CGFloat((hexNumber & 0x00ff0000) >> 16) / 255.0
                    let g = CGFloat((hexNumber & 0x0000ff00) >> 8) / 255.0
                    let b = CGFloat(hexNumber & 0x000000ff) / 255.0
                    self.init(red: r, green: g, blue: b, alpha: a)
                    return
                }
            }
        }
        return nil
    }
}

func NSColorFromRGB(_ rgbValue: Int) -> NSColor {
    return NSColor(
        red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
        green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
        blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
        alpha: 1.0
    )
}

// MARK: - Plugin Class

public class SwiftDeviceCalendarPlugin: NSObject, FlutterPlugin {
    
    // MARK: - Data Structures
    
    struct DeviceCalendar: Codable {
        let id: String
        let name: String
        let isReadOnly: Bool
        let isDefault: Bool
        let color: Int
        let accountName: String
        let accountType: String
    }
    
    struct Event: Codable {
        let eventId: String
        let calendarId: String
        let eventTitle: String
        let eventDescription: String?
        let eventStartDate: Int64
        let eventEndDate: Int64
        let eventStartTimeZone: String?
        let eventAllDay: Bool
        let attendees: [Attendee]
        let eventLocation: String?
        let eventURL: String?
        let recurrenceRule: RecurrenceRule?
        let organizer: Attendee?
        let reminders: [Reminder]
        let availability: Availability?
        let eventStatus: EventStatus?
    }
    
    struct RecurrenceRule: Codable {
        let freq: String
        let count: Int?
        let interval: Int
        let until: String?
        let byday: [String]?
        let bymonthday: [Int]?
        let byyearday: [Int]?
        let byweekno: [Int]?
        let bymonth: [Int]?
        let bysetpos: [Int]?
        let sourceRruleString: String?
    }
    
    struct Attendee: Codable {
        let name: String?
        let emailAddress: String
        let role: Int
        let attendanceStatus: Int
        let isCurrentUser: Bool
    }
    
    struct Reminder: Codable {
        let minutes: Int
    }
    
    enum Availability: String, Codable {
        case BUSY, FREE, TENTATIVE, UNAVAILABLE
    }
    
    enum EventStatus: String, Codable {
        case CONFIRMED, TENTATIVE, CANCELED, NONE
    }
    
    // MARK: - Constants
    
    static let channelName = "plugins.builttoroam.com/device_calendar"
    let notFoundErrorCode = "404"
    let notAllowed = "405"
    let genericError = "500"
    let unauthorizedErrorCode = "401"
    let unauthorizedErrorMessage = "The user has not allowed this application to modify their calendar(s)"
    let calendarNotFoundErrorMessageFormat = "The calendar with the ID %@ could not be found"
    let calendarReadOnlyErrorMessageFormat = "Calendar with ID %@ is read-only"
    let eventNotFoundErrorMessageFormat = "The event with the ID %@ could not be found"
    
    // Method names and argument keys
    let requestPermissionsMethod = "requestPermissions"
    let hasPermissionsMethod = "hasPermissions"
    let retrieveCalendarsMethod = "retrieveCalendars"
    let retrieveEventsMethod = "retrieveEvents"
    let createOrUpdateEventMethod = "createOrUpdateEvent"
    let createCalendarMethod = "createCalendar"
    let deleteCalendarMethod = "deleteCalendar"
    let deleteEventMethod = "deleteEvent"
    let deleteEventInstanceMethod = "deleteEventInstance"
    let showEventModalMethod = "showEventModal"
    let updateCalendarColor = "updateCalendarColor"
    let calendarIdArgument = "calendarId"
    let startDateArgument = "startDate"
    let endDateArgument = "endDate"
    let eventIdArgument = "eventId"
    let eventIdsArgument = "eventIds"
    let eventTitleArgument = "eventTitle"
    let eventDescriptionArgument = "eventDescription"
    let eventAllDayArgument = "eventAllDay"
    let eventStartDateArgument = "eventStartDate"
    let eventEndDateArgument = "eventEndDate"
    let eventStartTimeZoneArgument = "eventStartTimeZone"
    let eventLocationArgument = "eventLocation"
    let eventURLArgument = "eventURL"
    let attendeesArgument = "attendees"
    let recurrenceRuleArgument = "recurrenceRule"
    let recurrenceFrequencyArgument = "freq"
    let countArgument = "count"
    let intervalArgument = "interval"
    let untilArgument = "until"
    let byWeekDaysArgument = "byday"
    let byMonthDaysArgument = "bymonthday"
    let byYearDaysArgument = "byyearday"
    let byWeeksArgument = "byweekno"
    let byMonthsArgument = "bymonth"
    let bySetPositionsArgument = "bysetpos"
    let nameArgument = "name"
    let emailAddressArgument = "emailAddress"
    let roleArgument = "role"
    let remindersArgument = "reminders"
    let minutesArgument = "minutes"
    let followingInstancesArgument = "followingInstances"
    let calendarNameArgument = "calendarName"
    let calendarColorArgument = "calendarColor"
    let availabilityArgument = "availability"
    let attendanceStatusArgument = "attendanceStatus"
    let eventStatusArgument = "eventStatus"
    
    // MARK: - Instance Variables
    
    var eventStore = EKEventStore()
    
    // MARK: - Flutter Plugin Registration
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger)
        let instance = SwiftDeviceCalendarPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    // MARK: - Flutter Method Call Handler
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case requestPermissionsMethod:
            requestPermissions(result)
        case hasPermissionsMethod:
            hasPermissions(result)
        case retrieveCalendarsMethod:
            retrieveCalendars(result)
        case retrieveEventsMethod:
            retrieveEvents(call, result)
        case createOrUpdateEventMethod:
            createOrUpdateEvent(call, result)
        case deleteEventMethod:
            deleteEvent(call, result)
        case deleteEventInstanceMethod:
            deleteEvent(call, result)
        case createCalendarMethod:
            createCalendar(call, result)
        case deleteCalendarMethod:
            deleteCalendar(call, result)
        case showEventModalMethod:
            result(FlutterError(code: "UNSUPPORTED", message: "Event modal display is not supported on macOS", details: nil))
        case updateCalendarColor:
            updateCalendarColor(call, result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Permissions
    
    private func hasPermissions(_ result: @escaping FlutterResult) {
        result(hasEventPermissions())
    }
    
    private func requestPermissions(_ completion: @escaping (Bool) -> Void) {
        if hasEventPermissions() {
            completion(true)
            return
        }
        eventStore.requestAccess(to: .event) { (accessGranted: Bool, _: Error?) in
            completion(accessGranted)
        }
    }
    
    private func hasEventPermissions() -> Bool {
        return EKEventStore.authorizationStatus(for: .event) == .authorized
    }
    
    // MARK: - Calendar Operations
    
    private func getSource() -> EKSource? {
        let localSources = eventStore.sources.filter { $0.sourceType == .local }
        if !localSources.isEmpty { return localSources.first }
        if let defaultSource = eventStore.defaultCalendarForNewEvents?.source { return defaultSource }
        let iCloudSources = eventStore.sources.filter { $0.sourceType == .calDAV && $0.sourceIdentifier == "iCloud" }
        if !iCloudSources.isEmpty { return iCloudSources.first }
        return nil
    }
    
    private func createCalendar(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let arguments = call.arguments as! [String: AnyObject]
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        do {
            calendar.title = arguments[calendarNameArgument] as! String
            if let colorHex = arguments[calendarColorArgument] as? String,
               let nsColor = NSColor(hex: colorHex) {
                calendar.cgColor = nsColor.cgColor
            } else {
                calendar.cgColor = NSColor.red.cgColor
            }
            guard let source = getSource() else {
                result(FlutterError(code: genericError, message: "Local calendar was not found.", details: nil))
                return
            }
            calendar.source = source
            try eventStore.saveCalendar(calendar, commit: true)
            result(calendar.calendarIdentifier)
        } catch {
            eventStore.reset()
            result(FlutterError(code: genericError, message: error.localizedDescription, details: nil))
        }
    }
    
    private func updateCalendarColor(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let arguments = call.arguments as! [String: AnyObject]
        let calendarId = arguments[calendarIdArgument] as! String
        let color = arguments[calendarColorArgument] as! Int
        
        guard let calendar = eventStore.calendar(withIdentifier: calendarId) else {
            result(false)
            return
        }
        
        calendar.cgColor = NSColorFromRGB(color).cgColor
        
        do {
            try eventStore.saveCalendar(calendar, commit: true)
            result(true)
        } catch {
            result(FlutterError(code: genericError, message: error.localizedDescription, details: nil))
        }
    }
    
    private func deleteCalendar(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        checkPermissionsThenExecute(permissionsGrantedAction: {
            let arguments = call.arguments as! [String: AnyObject]
            let calendarId = arguments[calendarIdArgument] as! String
            
            guard let ekCalendar = self.eventStore.calendar(withIdentifier: calendarId) else {
                self.finishWithCalendarNotFoundError(result: result, calendarId: calendarId)
                return
            }
            
            if !ekCalendar.allowsContentModifications {
                self.finishWithCalendarReadOnlyError(result: result, calendarId: calendarId)
                return
            }
            
            do {
                try self.eventStore.removeCalendar(ekCalendar, commit: true)
                result(true)
            } catch {
                self.eventStore.reset()
                result(FlutterError(code: genericError, message: error.localizedDescription, details: nil))
            }
        }, result: result)
    }
    
    private func getAccountType(_ sourceType: EKSourceType) -> String {
        switch sourceType {
        case .local: return "Local"
        case .exchange: return "Exchange"
        case .calDAV: return "CalDAV"
        case .mobileMe: return "MobileMe"
        case .subscribed: return "Subscribed"
        case .birthdays: return "Birthdays"
        default: return "Unknown"
        }
    }
    
    private func retrieveCalendars(_ result: @escaping FlutterResult) {
        checkPermissionsThenExecute(permissionsGrantedAction: {
            let ekCalendars = self.eventStore.calendars(for: .event)
            let defaultCalendar = self.eventStore.defaultCalendarForNewEvents
            var calendars = [DeviceCalendar]()
            for ekCalendar in ekCalendars {
                let calendarColor = NSColor(cgColor: ekCalendar.cgColor)?.rgb() ?? 0
                let calendar = DeviceCalendar(
                    id: ekCalendar.calendarIdentifier,
                    name: ekCalendar.title,
                    isReadOnly: !ekCalendar.allowsContentModifications,
                    isDefault: defaultCalendar?.calendarIdentifier == ekCalendar.calendarIdentifier,
                    color: calendarColor,
                    accountName: ekCalendar.source.title,
                    accountType: self.getAccountType(ekCalendar.source.sourceType)
                )
                calendars.append(calendar)
            }
            self.encodeJsonAndFinish(codable: calendars, result: result)
        }, result: result)
    }
    
    // MARK: - Event Operations
    
    private func retrieveEvents(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        checkPermissionsThenExecute(permissionsGrantedAction: {
            let arguments = call.arguments as! [String: AnyObject]
            let calendarId = arguments[calendarIdArgument] as! String
            let startDateMillisecondsSinceEpoch = arguments[startDateArgument] as? NSNumber
            let endDateMillisecondsSinceEpoch = arguments[endDateArgument] as? NSNumber
            let eventIdArgs = arguments[eventIdsArgument] as? [String]
            var events = [Event]()
            let specifiedStartEndDates = startDateMillisecondsSinceEpoch != nil && endDateMillisecondsSinceEpoch != nil
            if specifiedStartEndDates {
                let startDate = Date(timeIntervalSince1970: startDateMillisecondsSinceEpoch!.doubleValue / 1000.0)
                let endDate = Date(timeIntervalSince1970: endDateMillisecondsSinceEpoch!.doubleValue / 1000.0)
                if let ekCalendar = self.eventStore.calendar(withIdentifier: calendarId) {
                    var ekEvents = [EKEvent]()
                    let fourYearsTimeInterval = TimeInterval(4 * 365 * 24 * 60 * 60)
                    var currentStartDate = startDate
                    var currentEndDate = startDate.addingTimeInterval(fourYearsTimeInterval)
                    while currentEndDate <= endDate {
                        let predicate = self.eventStore.predicateForEvents(withStart: currentStartDate, end: currentEndDate.addingTimeInterval(-1), calendars: [ekCalendar])
                        let batch = self.eventStore.events(matching: predicate)
                        ekEvents.append(contentsOf: batch)
                        currentStartDate = currentEndDate
                        currentEndDate = currentStartDate.addingTimeInterval(fourYearsTimeInterval)
                    }
                    if currentStartDate <= endDate {
                        let predicate = self.eventStore.predicateForEvents(withStart: currentStartDate, end: endDate, calendars: [ekCalendar])
                        let batch = self.eventStore.events(matching: predicate)
                        ekEvents.append(contentsOf: batch)
                    }
                    for ekEvent in ekEvents {
                        let event = createEventFromEkEvent(calendarId: calendarId, ekEvent: ekEvent)
                        events.append(event)
                    }
                }
            }
            
            if let eventIds = eventIdArgs, specifiedStartEndDates {
                events = events.filter { $0.calendarId == calendarId && eventIds.contains($0.eventId) }
                self.encodeJsonAndFinish(codable: events, result: result)
                return
            }
            
            if let eventIds = eventIdArgs, !specifiedStartEndDates {
                for eventId in eventIds {
                    if let ekEvent = self.eventStore.event(withIdentifier: eventId) {
                        let event = createEventFromEkEvent(calendarId: calendarId, ekEvent: ekEvent)
                        events.append(event)
                    }
                }
            }
            
            self.encodeJsonAndFinish(codable: events, result: result)
        }, result: result)
    }
    
    private func createEventFromEkEvent(calendarId: String, ekEvent: EKEvent) -> Event {
        var attendees = [Attendee]()
        if let ekAttendees = ekEvent.attendees {
            for ekParticipant in ekAttendees {
                if let attendee = convertEkParticipantToAttendee(ekParticipant: ekParticipant) {
                    attendees.append(attendee)
                }
            }
        }
        var reminders = [Reminder]()
        if let alarms = ekEvent.alarms {
            for alarm in alarms {
                reminders.append(Reminder(minutes: Int(-alarm.relativeOffset / 60)))
            }
        }
        let recurrenceRule = parseEKRecurrenceRules(ekEvent)
        return Event(
            eventId: ekEvent.eventIdentifier,
            calendarId: calendarId,
            eventTitle: ekEvent.title ?? "New Event",
            eventDescription: ekEvent.notes,
            eventStartDate: Int64(ekEvent.startDate.millisecondsSinceEpoch),
            eventEndDate: Int64(ekEvent.endDate.millisecondsSinceEpoch),
            eventStartTimeZone: ekEvent.timeZone?.identifier,
            eventAllDay: ekEvent.isAllDay,
            attendees: attendees,
            eventLocation: ekEvent.location,
            eventURL: ekEvent.url?.absoluteString,
            recurrenceRule: recurrenceRule,
            organizer: convertEkParticipantToAttendee(ekParticipant: ekEvent.organizer),
            reminders: reminders,
            availability: convertEkEventAvailability(ekEventAvailability: ekEvent.availability),
            eventStatus: convertEkEventStatus(ekEventStatus: ekEvent.status)
        )
    }
    
    private func convertEkParticipantToAttendee(ekParticipant: EKParticipant?) -> Attendee? {
        guard let participant = ekParticipant, let email = participant.emailAddress else { return nil }
        return Attendee(
            name: participant.name,
            emailAddress: email,
            role: participant.participantRole.rawValue,
            attendanceStatus: participant.participantStatus.rawValue,
            isCurrentUser: participant.isCurrentUser
        )
    }
    
    private func convertEkEventAvailability(ekEventAvailability: EKEventAvailability?) -> Availability? {
        switch ekEventAvailability {
        case .busy: return .BUSY
        case .free: return .FREE
        case .tentative: return .TENTATIVE
        case .unavailable: return .UNAVAILABLE
        default: return nil
        }
    }
    
    private func convertEkEventStatus(ekEventStatus: EKEventStatus?) -> EventStatus? {
        switch ekEventStatus {
        case .confirmed: return .CONFIRMED
        case .tentative: return .TENTATIVE
        case .canceled: return .CANCELED
        case .none?: return .NONE
        default: return nil
        }
    }
    
    private func parseEKRecurrenceRules(_ ekEvent: EKEvent) -> RecurrenceRule? {
        var recurrenceRule: RecurrenceRule?
        if ekEvent.hasRecurrenceRules, let ekRecurrenceRule = ekEvent.recurrenceRules?.first {
            let frequency: String
            switch ekRecurrenceRule.frequency {
            case .daily: frequency = "DAILY"
            case .weekly: frequency = "WEEKLY"
            case .monthly: frequency = "MONTHLY"
            case .yearly: frequency = "YEARLY"
            default: frequency = "DAILY"
            }
            
            let count = ekRecurrenceRule.recurrenceEnd?.occurrenceCount != 0 ? ekRecurrenceRule.recurrenceEnd?.occurrenceCount : nil
            let endDate = ekRecurrenceRule.recurrenceEnd?.endDate.flatMap { formateDateTime(dateTime: $0) }
            
            recurrenceRule = RecurrenceRule(
                freq: frequency,
                count: count,
                interval: ekRecurrenceRule.interval,
                until: endDate,
                byday: ekRecurrenceRule.daysOfTheWeek?.map { weekDayToString($0) },
                bymonthday: ekRecurrenceRule.daysOfTheMonth?.map { Int(truncating: $0) },
                byyearday: ekRecurrenceRule.daysOfTheYear?.map { Int(truncating: $0) },
                byweekno: ekRecurrenceRule.weeksOfTheYear?.map { Int(truncating: $0) },
                bymonth: ekRecurrenceRule.monthsOfTheYear?.map { Int(truncating: $0) },
                bysetpos: ekRecurrenceRule.setPositions?.map { Int(truncating: $0) },
                sourceRruleString: rruleStringFromEKRRule(ekRecurrenceRule)
            )
        }
        return recurrenceRule
    }
    
    private func weekDayToString(_ entry: EKRecurrenceDayOfWeek) -> String {
        let day = dayValueToString(entry.dayOfTheWeek.rawValue)
        return entry.weekNumber == 0 ? "\(day)" : "\(entry.weekNumber)\(day)"
    }
    
    private func dayValueToString(_ day: Int) -> String {
        switch day {
        case 1: return "SU"
        case 2: return "MO"
        case 3: return "TU"
        case 4: return "WE"
        case 5: return "TH"
        case 6: return "FR"
        case 7: return "SA"
        default: return "SU"
        }
    }
    
    private func formateDateTime(dateTime: Date) -> String {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        
        func twoDigits(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        func fourDigits(_ n: Int) -> String {
            let absolute = abs(n)
            let sign = n < 0 ? "-" : ""
            if absolute >= 1000 { return "\(n)" }
            if absolute >= 100 { return "\(sign)0\(absolute)" }
            if absolute >= 10 { return "\(sign)00\(absolute)" }
            return "\(sign)000\(absolute)"
        }
        
        let year = calendar.component(.year, from: dateTime)
        let month = calendar.component(.month, from: dateTime)
        let day = calendar.component(.day, from: dateTime)
        let hour = calendar.component(.hour, from: dateTime)
        let minute = calendar.component(.minute, from: dateTime)
        let second = calendar.component(.second, from: dateTime)
        
        let utcSuffix = calendar.timeZone == TimeZone(identifier: "UTC") ? "Z" : ""
        return "\(fourDigits(year))-\(twoDigits(month))-\(twoDigits(day))T\(twoDigits(hour)):\(twoDigits(minute)):\(twoDigits(second))\(utcSuffix)"
    }
    
    private func createEKRecurrenceRules(_ arguments: [String: AnyObject]) -> [EKRecurrenceRule]? {
        guard let recurrenceRuleArguments = arguments[recurrenceRuleArgument] as? [String: AnyObject] else { return nil }
        
        let recurrenceFrequency = recurrenceRuleArguments[recurrenceFrequencyArgument] as? String
        let totalOccurrences = recurrenceRuleArguments[countArgument] as? NSInteger
        let interval = recurrenceRuleArguments[intervalArgument] as? NSInteger
        let recurrenceInterval = (interval != nil && interval! > 1) ? interval! : 1
        var endDate = recurrenceRuleArguments[untilArgument] as? String
        
        var namedFrequency: EKRecurrenceFrequency
        switch recurrenceFrequency {
        case "YEARLY": namedFrequency = .yearly
        case "MONTHLY": namedFrequency = .monthly
        case "WEEKLY": namedFrequency = .weekly
        case "DAILY": namedFrequency = .daily
        default: namedFrequency = .daily
        }
        
        var recurrenceEnd: EKRecurrenceEnd?
        if let endDateStr = endDate {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            if !endDateStr.hasSuffix("Z") { endDate = endDateStr + "Z" }
            if let dateTime = dateFormatter.date(from: endDate!) {
                recurrenceEnd = EKRecurrenceEnd(end: dateTime)
            }
        } else if let occurrences = totalOccurrences, occurrences > 0 {
            recurrenceEnd = EKRecurrenceEnd(occurrenceCount: occurrences)
        }
        
        let byWeekDaysStrings = recurrenceRuleArguments[byWeekDaysArgument] as? [String]
        var byWeekDays = [EKRecurrenceDayOfWeek]()
        if let weekDayStrings = byWeekDaysStrings {
            for string in weekDayStrings {
                if let entry = recurrenceDayOfWeekFromString(recDay: string) {
                    byWeekDays.append(entry)
                }
            }
        }
        
        let byMonthDays = recurrenceRuleArguments[byMonthDaysArgument] as? [Int]
        let byYearDays = recurrenceRuleArguments[byYearDaysArgument] as? [Int]
        let byWeeks = recurrenceRuleArguments[byWeeksArgument] as? [Int]
        let byMonths = recurrenceRuleArguments[byMonthsArgument] as? [Int]
        let bySetPositions = recurrenceRuleArguments[bySetPositionsArgument] as? [Int]
        
        let ekrecurrenceRule = EKRecurrenceRule(
            recurrenceWith: namedFrequency,
            interval: recurrenceInterval,
            daysOfTheWeek: byWeekDays.isEmpty ? nil : byWeekDays,
            daysOfTheMonth: byMonthDays?.map { NSNumber(value: $0) },
            monthsOfTheYear: byMonths?.map { NSNumber(value: $0) },
            weeksOfTheYear: byWeeks?.map { NSNumber(value: $0) },
            daysOfTheYear: byYearDays?.map { NSNumber(value: $0) },
            setPositions: bySetPositions?.map { NSNumber(value: $0) },
            end: recurrenceEnd
        )
        return [ekrecurrenceRule]
    }
    
    private func rruleStringFromEKRRule(_ ekRrule: EKRecurrenceRule) -> String {
        var ekRRuleString = "\(ekRrule)"
        if let range = ekRRuleString.range(of: "RRULE ") {
            ekRRuleString = String(ekRRuleString[range.upperBound...])
        }
        return ekRRuleString
    }
    
    private func setAttendees(_ arguments: [String: AnyObject], _ ekEvent: EKEvent) {
        guard let attendeesArguments = arguments[attendeesArgument] as? [[String: AnyObject]] else { return }
        var attendees = [EKParticipant]()
        for attendeeArguments in attendeesArguments {
            let name = attendeeArguments[nameArgument] as! String
            let emailAddress = attendeeArguments[emailAddressArgument] as! String
            let role = attendeeArguments[roleArgument] as! Int
            if let existingAttendees = ekEvent.attendees,
               let existingAttendee = existingAttendees.first(where: { $0.emailAddress == emailAddress }),
               ekEvent.organizer?.emailAddress != existingAttendee.emailAddress {
                attendees.append(existingAttendee)
                continue
            }
            if let attendee = createParticipant(name: name, emailAddress: emailAddress, role: role) {
                attendees.append(attendee)
            }
        }
        ekEvent.setValue(attendees, forKey: "attendees")
    }
    
    private func createReminders(_ arguments: [String: AnyObject]) -> [EKAlarm]? {
        guard let remindersArguments = arguments[remindersArgument] as? [[String: AnyObject]] else { return nil }
        var reminders = [EKAlarm]()
        for reminderArguments in remindersArguments {
            let minutes = reminderArguments[minutesArgument] as! Int
            reminders.append(EKAlarm(relativeOffset: 60 * Double(-minutes)))
        }
        return reminders
    }
    
    private func recurrenceDayOfWeekFromString(recDay: String) -> EKRecurrenceDayOfWeek? {
        guard let results = recDay.match("(?:(\\+|-)?([0-9]{1,2}))?([A-Za-z]{2})").first else { return nil }
        var occurrence: Int?
        let numberMatch = results[1]
        if !numberMatch.isEmpty {
            occurrence = Int(numberMatch)
            if let occ = occurrence, occ < 1 || occ > 53 {
                print("OCCURRENCE_ERROR: OUT OF RANGE -> \(occ)")
            }
            if results[0] == "-" {
                occurrence = -(occurrence!)
            }
        }
        let dayMatch = results[2]
        var weekday: EKWeekday = .monday
        switch dayMatch {
        case "MO": weekday = .monday
        case "TU": weekday = .tuesday
        case "WE": weekday = .wednesday
        case "TH": weekday = .thursday
        case "FR": weekday = .friday
        case "SA": weekday = .saturday
        case "SU": weekday = .sunday
        default: weekday = .monday
        }
        if let occ = occurrence {
            return EKRecurrenceDayOfWeek(dayOfTheWeek: weekday, weekNumber: occ)
        } else {
            return EKRecurrenceDayOfWeek(weekday)
        }
    }
    
    private func setAvailability(_ arguments: [String: AnyObject]) -> EKEventAvailability? {
        guard let availabilityValue = arguments[availabilityArgument] as? String else { return .unavailable }
        switch availabilityValue.uppercased() {
        case Availability.BUSY.rawValue: return .busy
        case Availability.FREE.rawValue: return .free
        case Availability.TENTATIVE.rawValue: return .tentative
        case Availability.UNAVAILABLE.rawValue: return .unavailable
        default: return nil
        }
    }
    
    private func createOrUpdateEvent(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        checkPermissionsThenExecute(permissionsGrantedAction: {
            let arguments = call.arguments as! [String: AnyObject]
            let calendarId = arguments[calendarIdArgument] as! String
            let eventId = arguments[eventIdArgument] as? String
            let isAllDay = (arguments[eventAllDayArgument] as? Bool) ?? false
            let startDateMillisecondsSinceEpoch = arguments[eventStartDateArgument] as! NSNumber
            let endDateMillisecondsSinceEpoch = arguments[eventEndDateArgument] as! NSNumber
            let startDate = Date(timeIntervalSince1970: startDateMillisecondsSinceEpoch.doubleValue / 1000.0)
            let endDate = Date(timeIntervalSince1970: endDateMillisecondsSinceEpoch.doubleValue / 1000.0)
            let startTimeZoneString = arguments[eventStartTimeZoneArgument] as? String
            let title = arguments[self.eventTitleArgument] as? String
            let description = arguments[self.eventDescriptionArgument] as? String
            let location = arguments[self.eventLocationArgument] as? String
            let url = arguments[self.eventURLArgument] as? String
            
            guard let ekCalendar = self.eventStore.calendar(withIdentifier: calendarId) else {
                self.finishWithCalendarNotFoundError(result: result, calendarId: calendarId)
                return
            }
            if !ekCalendar.allowsContentModifications {
                self.finishWithCalendarReadOnlyError(result: result, calendarId: calendarId)
                return
            }
            
            var ekEvent: EKEvent?
            if eventId == nil {
                ekEvent = EKEvent(eventStore: self.eventStore)
            } else {
                ekEvent = self.eventStore.event(withIdentifier: eventId!)
                if ekEvent == nil {
                    self.finishWithEventNotFoundError(result: result, eventId: eventId!)
                    return
                }
            }
            
            ekEvent!.title = title ?? ""
            ekEvent!.notes = description
            ekEvent!.isAllDay = isAllDay
            ekEvent!.startDate = startDate
            ekEvent!.endDate = endDate
            if !isAllDay {
                let timeZone = TimeZone(identifier: startTimeZoneString ?? TimeZone.current.identifier) ?? .current
                ekEvent!.timeZone = timeZone
            }
            ekEvent!.calendar = ekCalendar
            ekEvent!.location = location
            if let urlCheck = url, !urlCheck.isEmpty, let eventUrl = URL(string: urlCheck) {
                ekEvent!.url = eventUrl
            } else {
                ekEvent!.url = nil
            }
            
            ekEvent!.recurrenceRules = createEKRecurrenceRules(arguments)
            setAttendees(arguments, ekEvent!)
            ekEvent!.alarms = createReminders(arguments)
            if let availability = setAvailability(arguments) {
                ekEvent!.availability = availability
            }
            do {
                try self.eventStore.save(ekEvent!, span: .futureEvents)
                result(ekEvent!.eventIdentifier)
            } catch {
                self.eventStore.reset()
                result(FlutterError(code: genericError, message: error.localizedDescription, details: nil))
            }
        }, result: result)
    }
    
    private func deleteEvent(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        checkPermissionsThenExecute(permissionsGrantedAction: {
            let arguments = call.arguments as! [String: AnyObject]
            let calendarId = arguments[calendarIdArgument] as! String
            let eventId = arguments[eventIdArgument] as! String
            let startDateNumber = arguments[eventStartDateArgument] as? NSNumber
            let endDateNumber = arguments[eventEndDateArgument] as? NSNumber
            let followingInstances = arguments[followingInstancesArgument] as? Bool
            
            guard let ekCalendar = self.eventStore.calendar(withIdentifier: calendarId) else {
                self.finishWithCalendarNotFoundError(result: result, calendarId: calendarId)
                return
            }
            if !ekCalendar.allowsContentModifications {
                self.finishWithCalendarReadOnlyError(result: result, calendarId: calendarId)
                return
            }
            
            if startDateNumber == nil && endDateNumber == nil && followingInstances == nil {
                if let ekEvent = self.eventStore.event(withIdentifier: eventId) {
                    do {
                        try self.eventStore.remove(ekEvent, span: .futureEvents)
                        result(true)
                    } catch {
                        self.eventStore.reset()
                        result(FlutterError(code: genericError, message: error.localizedDescription, details: nil))
                    }
                } else {
                    self.finishWithEventNotFoundError(result: result, eventId: eventId)
                }
            } else {
                let startDate = Date(timeIntervalSince1970: startDateNumber!.doubleValue / 1000.0)
                let endDate = Date(timeIntervalSince1970: endDateNumber!.doubleValue / 1000.0)
                let predicate = self.eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
                guard let foundEkEvents = self.eventStore.events(matching: predicate) as [EKEvent]?,
                      foundEkEvents.count > 0,
                      let ekEvent = foundEkEvents.first(where: { $0.eventIdentifier == eventId }) else {
                    self.finishWithEventNotFoundError(result: result, eventId: eventId)
                    return
                }
                do {
                    if followingInstances == false {
                        try self.eventStore.remove(ekEvent, span: .thisEvent, commit: true)
                    } else {
                        try self.eventStore.remove(ekEvent, span: .futureEvents, commit: true)
                    }
                    result(true)
                } catch {
                    self.eventStore.reset()
                    result(FlutterError(code: genericError, message: error.localizedDescription, details: nil))
                }
            }
        }, result: result)
    }
    
    // MARK: - Error Helpers
    
    private func finishWithUnauthorizedError(result: @escaping FlutterResult) {
        result(FlutterError(code: unauthorizedErrorCode, message: unauthorizedErrorMessage, details: nil))
    }
    
    private func finishWithCalendarNotFoundError(result: @escaping FlutterResult, calendarId: String) {
        let errorMessage = String(format: calendarNotFoundErrorMessageFormat, calendarId)
        result(FlutterError(code: notFoundErrorCode, message: errorMessage, details: nil))
    }
    
    private func finishWithCalendarReadOnlyError(result: @escaping FlutterResult, calendarId: String) {
        let errorMessage = String(format: calendarReadOnlyErrorMessageFormat, calendarId)
        result(FlutterError(code: notAllowed, message: errorMessage, details: nil))
    }
    
    private func finishWithEventNotFoundError(result: @escaping FlutterResult, eventId: String) {
        let errorMessage = String(format: eventNotFoundErrorMessageFormat, eventId)
        result(FlutterError(code: notFoundErrorCode, message: errorMessage, details: nil))
    }
    
    private func encodeJsonAndFinish<T: Codable>(codable: T, result: @escaping FlutterResult) {
        do {
            let jsonEncoder = JSONEncoder()
            let jsonData = try jsonEncoder.encode(codable)
            let jsonString = String(data: jsonData, encoding: .utf8)
            result(jsonString)
        } catch {
            result(FlutterError(code: genericError, message: error.localizedDescription, details: nil))
        }
    }
    
    private func checkPermissionsThenExecute(permissionsGrantedAction: () -> Void, result: @escaping FlutterResult) {
        if hasEventPermissions() {
            permissionsGrantedAction()
        } else {
            self.finishWithUnauthorizedError(result: result)
        }
    }
    
    // MARK: - createParticipant Implementation
    
    private func createParticipant(name: String, emailAddress: String, role: Int) -> EKParticipant? {
        if let ekAttendeeClass = NSClassFromString("EKAttendee") as? NSObject.Type {
            let participant = ekAttendeeClass.init()
            participant.setValue(UUID().uuidString, forKey: "UUID")
            participant.setValue(name, forKey: "displayName")
            participant.setValue(emailAddress, forKey: "emailAddress")
            participant.setValue(role, forKey: "participantRole")
            return participant as? EKParticipant
        }
        return nil
    }
}