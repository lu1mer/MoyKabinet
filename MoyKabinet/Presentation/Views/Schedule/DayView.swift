import SwiftUI

struct BookingRequest: Identifiable { let id = UUID(); var date: Date }

struct DayView: View {
    @EnvironmentObject var store: CabinetStore
    @EnvironmentObject var online: OnlineManager
    var isCalendar: Bool
    @State private var selectedDate = Date()
    @State private var bookingRequest: BookingRequest?
    @State private var showMonth = false
    @State private var showCancelled = false
    private var date: Date { isCalendar ? selectedDate : .now }
    private var model: DayViewModel { DayViewModel(data: store.data, calendar: store.calendar, date: date) }
    private var visits: [Appointment] { model.visits }
    private var active: [Appointment] { visits.filter { $0.status != .cancelled } }
    private var visible: [Appointment] { visits.filter { showCancelled || $0.status != .cancelled } }
    private var next: Appointment? { active.first { $0.status == .planned && $0.end > .now } }
    private var profession: ProfessionPreset { store.data.settings.professionPreset }
    private func book(_ date: Date) { bookingRequest = BookingRequest(date: date) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 27) {
                    header
                    if online.failed && online.credentials != nil {
                        NavigationLink { OnlineView() } label: {
                            Label("Проверьте синхронизацию", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption.weight(.semibold))
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(Style.accent)
                                .background(Style.accentSoft, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    if isCalendar {
                        weekStrip
                        if showMonth {
                            DatePicker("Дата", selection: $selectedDate, displayedComponents: .date)
                                .datePickerStyle(.graphical).cardSurface()
                        }
                    } else {
                        hero
                        summary
                    }
                    schedule
                    if let slot = model.nextSlot {
                        Button { book(slot) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus").font(.system(size: 15, weight: .bold))
                                    .frame(width: 36, height: 36)
                                    .background(Style.accentSoft, in: Circle())
                                Text("Свободно в \(slot.time(in: store.calendar.timeZone))")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.caption.weight(.bold))
                            }
                            .foregroundStyle(Style.accent)
                            .padding(14)
                            .background(Style.card, in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain)
                    }
                    if !store.loaded {
                        Label("Восстановите данные в Кабинете", systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(Style.accent)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(Style.background)
            .navigationDestination(for: UUID.self) { VisitDetailView(visitID: $0) }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: model.nextSlot.map { "\(profession.appointmentTitle) · \($0.time(in: store.calendar.timeZone))" } ?? profession.newAppointmentTitle) {
                    book(model.nextSlot ?? date)
                }
                .accessibilityLabel("Новая запись")
                .padding(.horizontal, 22)
                .padding(.vertical, 9)
                .background(Style.background.opacity(0.96))
            }
            .sheet(item: $bookingRequest) { BookingForm(date: $0.date) }
            .feedback()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("м.")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .tracking(-2)
                    .foregroundStyle(Style.accent)
                    .accessibilityLabel("Мой кабинет")
                Spacer()
                if isCalendar {
                    Button { showMonth.toggle() } label: {
                        Image(systemName: showMonth ? "calendar.badge.minus" : "calendar")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 42, height: 42)
                            .background(Style.card, in: Circle())
                    }.accessibilityLabel("Показать месяц")
                } else {
                    Text(date.ruFormatted(.dateTime.day().month(.abbreviated), in: store.calendar.timeZone))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Style.muted)
                }
            }
            Text(isCalendar ? "Расписание" : "Сегодня")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .tracking(-1.8)
                .foregroundStyle(Style.ink)
                .minimumScaleFactor(0.75)
            if isCalendar {
                Text(date.ruFormatted(.dateTime.weekday(.wide).day().month(.wide), in: store.calendar.timeZone).capitalized)
                    .font(.subheadline).foregroundStyle(Style.muted)
            }
        }
    }

    private var hero: some View {
        NavigationLink(value: next?.id) {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Text(next == nil ? "В РИТМЕ" : "СЛЕДУЮЩАЯ \(profession.appointmentTitle.uppercased())")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(2)
                    Spacer()
                    Image(systemName: next == nil ? "sparkle" : "arrow.up.right")
                        .font(.system(size: 18, weight: .semibold))
                }
                .opacity(0.86)
                if let next {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(model.clientName(for: next))
                                .font(.system(size: 27, weight: .bold, design: .rounded))
                                .lineLimit(2)
                            Text(next.serviceName).font(.subheadline).opacity(0.8)
                        }
                        Spacer(minLength: 8)
                        Text(next.start.time(in: store.calendar.timeZone))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Всё под контролем.")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(active.isEmpty ? "Пока без записей" : "\(active.count) событий сегодня")
                            .font(.subheadline).opacity(0.85)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Style.gradient, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .shadow(color: Style.accent.opacity(0.22), radius: 20, y: 12)
        }
        .buttonStyle(.plain)
        .disabled(next == nil)
    }

    private var summary: some View {
        HStack(spacing: 12) {
            metric("ПЛАН", active.reduce(0) { $0 + $1.price }.rubles)
            metric("ОПЛАЧЕНО", visits.filter { $0.status == .paid }.reduce(0) { $0 + $1.price }.rubles)
        }
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Eyebrow(text: title)
            Text(value)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .tracking(-0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Style.card, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(Style.line, lineWidth: 1))
    }

    private var weekStrip: some View {
        VStack(spacing: 12) {
            HStack {
                Button { selectedDate = store.calendar.date(byAdding: .day, value: -7, to: selectedDate) ?? selectedDate } label: {
                    Image(systemName: "chevron.left").frame(width: 40, height: 32)
                }.accessibilityLabel("Предыдущая неделя")
                Spacer()
                Button("Сегодня") { selectedDate = .now }.font(.subheadline.weight(.semibold))
                Spacer()
                Button { selectedDate = store.calendar.date(byAdding: .day, value: 7, to: selectedDate) ?? selectedDate } label: {
                    Image(systemName: "chevron.right").frame(width: 40, height: 32)
                }.accessibilityLabel("Следующая неделя")
            }
            HStack(spacing: 3) {
                let start = store.calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
                ForEach(0..<7) { offset in
                    let day = store.calendar.date(byAdding: .day, value: offset, to: start) ?? start
                    let selected = store.calendar.isDate(day, inSameDayAs: selectedDate)
                    Button { selectedDate = day } label: {
                        VStack(spacing: 7) {
                            Text(day.ruFormatted(.dateTime.weekday(.abbreviated), in: store.calendar.timeZone))
                                .font(.system(size: 10, weight: .semibold))
                            Text(day.ruFormatted(.dateTime.day(), in: store.calendar.timeZone))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                            Circle().fill(store.visits(on: day).contains { $0.status != .cancelled } ? (selected ? Color.white : Style.accent) : .clear)
                                .frame(width: 4, height: 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(selected ? .white : Style.ink)
                        .background(selected ? Style.accent : Style.card, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                SectionHeading(title: profession.appointmentsTitle, detail: "\(active.count)")
                if visits.contains(where: { $0.status == .cancelled }) {
                    Button(showCancelled ? "Скрыть отмены" : "Отменённые") { showCancelled.toggle() }
                        .font(.caption.weight(.medium))
                }
            }
            if visible.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundStyle(Style.accent)
                    Text("Пока пусто")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                    if store.data.clients.isEmpty && store.data.appointments.isEmpty {
                        Button("Посмотреть пример") { store.addDemo() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Style.accent)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 38)
                .cardSurface()
            } else {
                ForEach(visible) { visit in
                    NavigationLink(value: visit.id) {
                        VisitCard(visit: visit, name: model.clientName(for: visit))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct VisitCard: View {
    @EnvironmentObject var store: CabinetStore
    let visit: Appointment
    let name: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(visit.start.time(in: store.calendar.timeZone))
                    .font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
                Text(visit.end.time(in: store.calendar.timeZone))
                    .font(.caption).foregroundStyle(Style.muted).monospacedDigit()
            }.frame(width: 48, alignment: .leading)
            RoundedRectangle(cornerRadius: 2)
                .fill(visit.status == .cancelled ? Style.line : Style.accent)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 6) {
                        if visit.calendarEventID != nil { Image(systemName: "calendar").font(.caption).foregroundStyle(Style.accent) }
                        Text(name).font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Style.muted)
                }
                Text(visit.serviceName).font(.caption).foregroundStyle(Style.muted)
                HStack {
                    HStack(spacing: 5) {
                        Circle().fill(visit.status == .paid ? Style.accent : Style.muted.opacity(0.55))
                            .frame(width: 5, height: 5)
                        Text(visit.calendarEventID != nil ? "Из календаря" : (visit.status == .planned ? "Ожидается" : visit.status.rawValue))
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(visit.status == .paid ? Style.accent : Style.muted)
                    Spacer()
                    if visit.calendarEventID == nil { Text(visit.price.rubles).font(.caption.weight(.bold)) }
                }
            }
        }
        .padding(17)
        .background(Style.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Style.line, lineWidth: 1))
        .opacity(visit.status == .cancelled ? 0.55 : 1)
    }
}

struct VisitDetailView: View {
    @EnvironmentObject var store: CabinetStore
    let visitID: UUID
    @State private var confirmCancel = false
    @State private var confirmSeriesCancel = false
    @State private var editing = false
    private var visit: Appointment? { store.data.appointments.first { $0.id == visitID } }
    var body: some View {
        Group {
            if let visit {
                List {
                    Section {
                        if visit.calendarEventID == nil, let client = store.client(visit.clientID) {
                            NavigationLink { ClientDetailView(clientID: client.id) } label: {
                                HStack(spacing: 14) { ClientAvatar(client: client, size: 52); VStack(alignment: .leading, spacing: 5) { Text(client.name).font(.headline); Text("Карточка клиента").font(.caption).foregroundStyle(.secondary) } }.padding(.vertical, 8)
                            }
                        }
                    }
                    Section("Детали") {
                        LabeledContent("Услуга", value: visit.serviceName)
                        LabeledContent("Дата", value: visit.start.ruFormatted(Date.FormatStyle(date: .abbreviated, time: .shortened), in: store.calendar.timeZone))
                        LabeledContent("Длительность", value: "\(visit.minutes) мин")
                        if visit.calendarEventID == nil { LabeledContent("Стоимость", value: visit.price.rubles) }
                        if let calendarName = visit.calendarName { LabeledContent("Источник", value: calendarName) }
                        if let index = visit.recurrenceIndex { LabeledContent("Повтор", value: "№ \(index + 1) в серии") }
                        LabeledContent("Статус", value: visit.status.rawValue)
                        if let note = visit.note, !note.isEmpty { Text(note).font(.callout).foregroundStyle(.secondary) }
                    }
                    Section {
                        if visit.calendarEventID != nil {
                            Label("Событие управляется в системном календаре", systemImage: "calendar.badge.checkmark")
                                .font(.callout).foregroundStyle(.secondary)
                        } else if visit.status == .planned {
                            Button { _ = store.setStatus(visit.id, .paid) } label: { Label("Отметить оплату", systemImage: "checkmark.circle") }.accessibilityIdentifier("markPaid")
                            Button { editing = true } label: { Label("Перенести или изменить", systemImage: "calendar.badge.clock") }
                            Button("Отменить запись", role: .destructive) { confirmCancel = true }
                            if visit.recurrenceSeriesID != nil {
                                Button("Отменить эту и следующие", role: .destructive) { confirmSeriesCancel = true }
                            }
                        } else if visit.status == .paid {
                            Button("Убрать отметку об оплате") { _ = store.setStatus(visit.id, .planned) }
                        } else {
                            Button("Восстановить запись") { _ = store.setStatus(visit.id, .planned) }
                        }
                    }
                }.cabinetBackground()
                    .sheet(isPresented: $editing) { BookingForm(date: visit.start, visit: visit) }
            } else { ContentUnavailableView("Запись не найдена", systemImage: "calendar") }
        }.navigationTitle("Запись").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Отменить запись? Время станет свободным, история сохранится.", isPresented: $confirmCancel, titleVisibility: .visible) {
                Button("Отменить запись", role: .destructive) { _ = store.setStatus(visitID, .cancelled) }
            }
            .confirmationDialog("Отменить эту и все следующие записи серии? Прошлые занятия останутся в истории.", isPresented: $confirmSeriesCancel, titleVisibility: .visible) {
                if let visit, let seriesID = visit.recurrenceSeriesID {
                    Button("Отменить остаток серии", role: .destructive) { _ = store.cancelSeries(seriesID, from: visit.start) }
                }
            }.feedback()
    }
}
