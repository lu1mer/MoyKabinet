import Foundation

extension Int {
    var rubles: String { formatted(.currency(code: "RUB").precision(.fractionLength(0)).locale(Locale(identifier: "ru_RU"))) }
}

extension Date {
    var shortTime: String { time(in: .current) }
    func ruFormatted(_ format: Date.FormatStyle, in zone: TimeZone) -> String {
        var style = format; style.timeZone = zone; style.locale = Locale(identifier: "ru_RU")
        return formatted(style)
    }
    func time(in zone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.locale = Locale(identifier: "ru_RU"); style.timeZone = zone
        return formatted(style)
    }
}
