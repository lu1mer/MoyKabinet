import SwiftUI

struct BookingForm: View {
    @EnvironmentObject private var store: CabinetStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: BookingFormViewModel
    @State private var clientPicker = false
    @State private var newClient = false
    @State private var showDetails = false
    @State private var pickingDate = false
    @State private var pickingTime = false
    @State private var dayAnchor: Date

    init(date: Date, visit: Appointment? = nil, clientID: UUID? = nil) {
        let draft = BookingFormViewModel(date: date, editing: visit, clientID: clientID)
        _model = StateObject(wrappedValue: draft)
        _dayAnchor = State(initialValue: draft.start)
    }

    private var actionTitle: String {
        let verb = model.editing == nil ? "Записать" : "Сохранить"
        let time = model.start.time(in: store.calendar.timeZone)
        if model.seriesStarts.count > 1 { return "Создать серию · \(model.seriesStarts.count)" }
        if let price = Int(model.priceText) { return "\(verb) · \(time) · \(price.rubles)" }
        return "\(verb) · \(time)"
    }

    private var profession: ProfessionPreset { store.data.settings.professionPreset }

    var body: some View {
        NavigationStack {
            ZStack {
                VibeBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        momentCard
                        clientCard
                        servicePicker
                        if model.editing == nil { recurrenceCard }
                        if model.conflict { conflictCard }
                        detailsCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: actionTitle, icon: "arrow.up.right") {
                    let items = model.appointments()
                    guard !items.isEmpty else { return }
                    if store.saveVisits(items) { dismiss() }
                }
                .disabled(!model.canSave)
                .opacity(model.canSave ? 1 : 0.42)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(.ultraThinMaterial)
                .accessibilityIdentifier("saveBooking")
            }
            .navigationTitle(model.editing == nil ? profession.newAppointmentTitle : "Изменить \(profession.appointmentTitle.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .onAppear { model.configure(with: store.data) }
            .onChange(of: store.data) { _, value in model.update(data: value) }
            .onChange(of: model.start) { _, value in
                if !dayChoices.contains(where: { store.calendar.isDate($0, inSameDayAs: value) }) {
                    dayAnchor = value
                }
            }
            .sheet(isPresented: $clientPicker) {
                ClientPickerSheet(selection: $model.clientID)
                    .environmentObject(store)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $newClient) {
                ClientForm(onSave: { model.clientID = $0 })
                    .environmentObject(store)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $pickingDate) {
                BookingDateSheet(selection: $model.start, calendar: store.calendar)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $pickingTime) {
                BookingTimeSheet(selection: $model.start, calendar: store.calendar)
                    .presentationDetents([.height(340)])
                    .presentationDragIndicator(.visible)
            }
            .feedback()
        }
    }

    private var momentCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "КОГДА")
                    Text(model.start.ruFormatted(.dateTime.weekday(.wide).day().month(.wide), in: store.calendar.timeZone).capitalized)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Style.ink)
                }
                Spacer()
                VibeIconButton(systemName: "calendar", accessibilityLabel: "Выбрать дату") {
                    pickingDate = true
                }
            }

            dayStrip

            Button { pickingTime = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "clock.fill").foregroundStyle(Style.accent)
                    Text(model.start.time(in: store.calendar.timeZone))
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("до \(model.start.addingTimeInterval(Double(model.minutes) * 60).time(in: store.calendar.timeZone))")
                            .font(.subheadline.weight(.semibold))
                        Text("\(model.minutes) мин")
                            .font(.caption)
                            .foregroundStyle(Style.muted)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Style.muted)
                }
                .padding(.horizontal, 16)
                .frame(height: 58)
                .background(Style.accentSoft, in: RoundedRectangle(cornerRadius: 17))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Время начала")
            .accessibilityValue(model.start.time(in: store.calendar.timeZone))

            let slots = model.availableSlots(calendar: store.calendar)
            if !slots.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ближайшее свободное")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Style.muted)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(slots, id: \.self) { slot in
                                let selected = store.calendar.compare(slot, to: model.start, toGranularity: .minute) == .orderedSame
                                Button(slot.time(in: store.calendar.timeZone)) {
                                    withAnimation(.snappy) { model.start = slot }
                                }
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(selected ? Color.white : Style.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(selected ? AnyShapeStyle(Style.gradient) : AnyShapeStyle(Style.accentSoft), in: Capsule())
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(20)
        .vibeCard(radius: 26)
    }

    private var dayStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(dayChoices, id: \.self) { day in
                    let selected = store.calendar.isDate(day, inSameDayAs: model.start)
                    Button {
                        withAnimation(.snappy) { model.setDay(day, calendar: store.calendar) }
                    } label: {
                        VStack(spacing: 4) {
                            Text(day.ruFormatted(.dateTime.weekday(.abbreviated), in: store.calendar.timeZone).uppercased())
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                            Text(day.ruFormatted(.dateTime.day(), in: store.calendar.timeZone))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                        }
                        .frame(width: 50, height: 58)
                        .foregroundStyle(selected ? Color.white : Style.ink)
                        .background(selected ? AnyShapeStyle(Style.gradient) : AnyShapeStyle(Style.accentSoft.opacity(0.72)), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }

    private var dayChoices: [Date] {
        (0..<5).compactMap {
            store.calendar.date(byAdding: .day, value: $0, to: store.calendar.startOfDay(for: dayAnchor))
        }
    }

    private var clientCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeading(title: profession.clientTitle)
                Spacer()
                if model.selectedClient != nil {
                    Button("Сменить") { clientPicker = true }
                        .font(.subheadline.weight(.semibold))
                }
            }

            if let client = model.selectedClient {
                Button { clientPicker = true } label: {
                    HStack(spacing: 14) {
                        ClientAvatar(client: client, size: 52)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(client.name)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                            if !client.phone.isEmpty {
                                Text(client.phone).font(.caption).foregroundStyle(Style.muted)
                            } else {
                                Text("Выбран для записи").font(.caption).foregroundStyle(Style.muted)
                            }
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Style.accent)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Button { clientPicker = true } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 42, height: 42)
                            .background(Style.accentSoft, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Выбрать \(profession.clientTitle.lowercased())а").font(.headline)
                            Text("По имени или телефону").font(.caption).foregroundStyle(Style.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Style.muted)
                    }
                }
                .buttonStyle(.plain)
            }

            Divider().overlay(Style.line)

            Button { newClient = true } label: {
                Label("Новый \(profession.clientTitle.lowercased())", systemImage: "person.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Style.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("newClient")
        }
        .padding(20)
        .vibeCard()
    }

    private var servicePicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: profession.serviceTitle, detail: model.serviceName.isEmpty ? nil : "\(model.minutes) мин")

            if model.activeServices.isEmpty && model.serviceName.isEmpty {
                Label("Сначала добавьте \(profession.serviceTitle.lowercased()) в Кабинете", systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(Style.muted)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .vibeCard(radius: 18)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 11) {
                        if model.editing != nil && model.serviceID == nil {
                            serviceChoice(name: model.serviceName, minutes: model.minutes, price: Int(model.priceText) ?? 0, selected: true) { }
                        }
                        ForEach(model.activeServices) { service in
                            serviceChoice(name: service.name, minutes: service.minutes, price: service.price, selected: model.serviceID == service.id) {
                                withAnimation(.snappy) { model.select(service) }
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
                .scrollClipDisabled()
            }
        }
    }

    private func serviceChoice(name: String, minutes: Int, price: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: selected ? "checkmark" : "sparkle")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(selected ? Color.white : Style.accent)
                        .background(selected ? Color.white.opacity(0.2) : Style.accentSoft, in: Circle())
                    Spacer()
                    Text("\(minutes) мин").font(.caption.weight(.semibold)).opacity(0.75)
                }
                Text(name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(price.rubles)
                    .font(.subheadline.weight(.bold))
            }
            .padding(16)
            .frame(width: 172, height: 145, alignment: .leading)
            .foregroundStyle(selected ? Color.white : Style.ink)
            .background(selected ? AnyShapeStyle(Style.gradient) : AnyShapeStyle(Style.card), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(selected ? Color.clear : Style.line, lineWidth: 1))
            .shadow(color: selected ? Style.accent.opacity(0.20) : .clear, radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var conflictCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.conflictingSeriesStarts.count > 1 ? "Несколько повторов пересекаются" : "Это время уже занято", systemImage: "exclamationmark.circle.fill")
                .font(.headline)
                .foregroundStyle(Style.accent)
            if let slot = model.suggestedSlot {
                Button("Выбрать свободное · \(slot.time(in: store.calendar.timeZone))") {
                    withAnimation(.snappy) { model.start = slot }
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Style.accent)
            }
            if model.seriesStarts.count > 1 {
                Text(model.conflictingSeriesStarts.prefix(3).map { $0.ruFormatted(.dateTime.day().month(.abbreviated).hour().minute(), in: store.calendar.timeZone) }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Style.muted)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Style.accentSoft, in: RoundedRectangle(cornerRadius: 20))
    }

    private var recurrenceCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 13) {
                Image(systemName: "repeat")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 42, height: 42)
                    .foregroundStyle(Style.accent)
                    .background(Style.accentSoft, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Повтор").font(.headline)
                    Text(model.recurrence == .none ? "Один раз" : model.recurrence.title)
                        .font(.caption).foregroundStyle(Style.muted)
                }
                Spacer()
                Picker("Повтор", selection: $model.recurrence) {
                    ForEach(RecurrencePattern.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Style.accent)
            }
            if model.recurrence != .none {
                Divider().overlay(Style.line)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Сколько раз").font(.subheadline.weight(.semibold))
                        Text("До \(model.seriesStarts.last?.ruFormatted(.dateTime.day().month(.wide), in: store.calendar.timeZone) ?? "—")")
                            .font(.caption).foregroundStyle(Style.muted)
                    }
                    Spacer()
                    Stepper("\(model.repeatCount)", value: $model.repeatCount, in: 2...52)
                        .fixedSize()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .vibeCard(radius: 21)
        .animation(.snappy, value: model.recurrence)
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) { showDetails.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Дополнительно").font(.headline)
                        Text("Цена, длительность и заметка").font(.caption).foregroundStyle(Style.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(showDetails ? 180 : 0))
                        .foregroundStyle(Style.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showDetails {
                Divider().overlay(Style.line).padding(.vertical, 18)
                VStack(spacing: 18) {
                    HStack {
                        Label("Длительность", systemImage: "timer")
                        Spacer()
                        Stepper("\(model.minutes) минут", value: $model.minutes, in: 15...480, step: 15)
                            .labelsHidden()
                        Text("\(model.minutes) мин")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 64, alignment: .trailing)
                    }
                    Divider().overlay(Style.line)
                    HStack {
                        Label("Стоимость", systemImage: "rublesign.circle")
                        Spacer()
                        TextField("0", text: $model.priceText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: 110)
                        Text("₽").foregroundStyle(Style.muted)
                    }
                    Divider().overlay(Style.line)
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Заметка", systemImage: "text.alignleft")
                        TextField("Пожелания или детали…", text: $model.note, axis: .vertical)
                            .lineLimit(2...5)
                            .padding(14)
                            .background(Style.accentSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 15))
                    }
                }
                .font(.subheadline)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(20)
        .vibeCard()
    }
}

private struct BookingDateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Date
    let calendar: Calendar

    var body: some View {
        NavigationStack {
            DatePicker("Дата", selection: $selection, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(Style.accent)
                .padding(.horizontal, 18)
                .navigationTitle("Выберите дату")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}

private struct BookingTimeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Date
    let calendar: Calendar

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker("Время", selection: $selection, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .tint(Style.accent)
                Text("Шаг можно уточнить быстрыми слотами на экране записи")
                    .font(.caption)
                    .foregroundStyle(Style.muted)
            }
            .navigationTitle("Время начала")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .environment(\.calendar, calendar)
    }
}

private struct ClientPickerSheet: View {
    @EnvironmentObject private var store: CabinetStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: UUID?
    @State private var query = ""
    @State private var adding = false

    private var clients: [Client] {
        store.activeClients.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.phone.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VibeBackground()
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(clients) { client in
                            Button {
                                selection = client.id
                                dismiss()
                            } label: {
                                HStack(spacing: 14) {
                                    ClientAvatar(client: client, size: 48)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(client.name).font(.body.weight(.semibold))
                                        if !client.phone.isEmpty { Text(client.phone).font(.caption).foregroundStyle(Style.muted) }
                                    }
                                    Spacer()
                                    Image(systemName: selection == client.id ? "checkmark.circle.fill" : "chevron.right")
                                        .foregroundStyle(selection == client.id ? Style.accent : Style.muted)
                                }
                                .padding(16)
                                .contentShape(Rectangle())
                                .vibeCard(radius: 19)
                            }
                            .buttonStyle(.plain)
                        }

                        if clients.isEmpty {
                            ContentUnavailableView("Клиент не найден", systemImage: "person.crop.circle.badge.questionmark", description: Text("Создайте нового — достаточно имени."))
                                .padding(.top, 48)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Выберите клиента")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Имя или телефон")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { adding = true } label: { Image(systemName: "person.badge.plus") }
                        .accessibilityLabel("Новый клиент")
                }
            }
            .sheet(isPresented: $adding) {
                ClientForm(onSave: { id in selection = id; dismiss() })
                    .environmentObject(store)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}
