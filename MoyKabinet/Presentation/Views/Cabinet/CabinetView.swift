import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct CabinetView: View {
    @EnvironmentObject var store: CabinetStore
    @EnvironmentObject var online: OnlineManager
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var calendarImport: CalendarImportManager
    @State private var addingService = false
    @State private var editService: Service?
    @State private var showArchived = false
    @State private var profile = false
    @State private var exporting = false
    @State private var importing = false
    @State private var document = BackupDocument(data: Data())
    @State private var pendingImport: Data?
    @State private var confirmRestore = false
    @State private var deleting = false
    @State private var backupError: String?
    @State private var notice: String?
    @State private var authPresented = false
    private var model: CabinetViewModel { CabinetViewModel(data: store.data, calendar: store.calendar) }
    private var profession: ProfessionPreset { store.data.settings.professionPreset }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 16) {
                            Eyebrow(text: profession.title)
                                .foregroundStyle(.white.opacity(0.78))
                            Text(store.data.settings.name)
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .tracking(-1.2)
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Text(store.data.settings.specialty)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text("м.")
                            .font(.system(size: 29, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: 158, alignment: .leading)
                    .background(Style.gradient, in: RoundedRectangle(cornerRadius: 24))
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                }
                Section("Итоги") {
                    NavigationLink { ReportsView() } label: { LabeledContent("Оплачено за месяц", value: model.monthlyPaid.rubles) }
                    LabeledContent("Активных клиентов", value: "\(model.activeClientCount)")
                }
                Section {
                    ForEach(model.services(showArchived: showArchived)) { service in
                        Button { editService = service } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(service.name).foregroundStyle(Style.ink)
                                    Text("\(service.minutes) мин\(service.archived == true ? " · в архиве" : "")").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(); Text(service.price.rubles).font(.subheadline).foregroundStyle(Style.ink)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }.padding(.vertical, 5)
                        }
                    }
                    Button { addingService = true } label: { Label("Добавить \(profession.serviceTitle.lowercased())", systemImage: "plus") }
                    if store.data.services.contains(where: { $0.archived == true }) { Toggle("Показать архив", isOn: $showArchived).font(.subheadline) }
                } header: { Text(profession.servicesTitle) }
                Section("Настройки") {
                    Button { profile = true } label: { Label("Профиль и рабочие часы", systemImage: "slider.horizontal.3") }
                    NavigationLink { AppearanceSettingsView() } label: { Label("Вид и направление", systemImage: "paintpalette") }
                    NavigationLink { CalendarIntegrationView() } label: {
                        Label(calendarImport.enabled ? "Календарь подключён" : "Системный календарь", systemImage: "calendar.badge.plus")
                    }
                    Toggle(isOn: Binding(get: { store.data.settings.reminders }, set: { enabled in Task { await store.setReminders(enabled) } })) { Label("Напомнить за 30 минут", systemImage: "bell") }
                    NavigationLink { OnlineView() } label: { Label("Онлайн-запись", systemImage: "link") }
                }
                Section("Аккаунт") {
                    if let session = auth.session {
                        Button { authPresented = true } label: {
                            Label(session.user.displayName ?? session.user.email ?? "Аккаунт подключён", systemImage: "person.crop.circle.fill")
                        }
                        Button("Выйти", role: .destructive) { Task { await auth.signOut() } }
                    } else {
                        Button { authPresented = true } label: {
                            Label("Войти или создать аккаунт", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                }
                Section {
                    Button {
                        do { document = BackupDocument(data: try store.exportData()); exporting = true }
                        catch { backupError = error.localizedDescription }
                    } label: { Label("Сохранить резервную копию", systemImage: "square.and.arrow.up") }
                    Button { importing = true } label: { Label("Восстановить из копии", systemImage: "square.and.arrow.down") }
                    NavigationLink { PrivacyView() } label: { Label("Данные и конфиденциальность", systemImage: "hand.raised") }
                } header: { Text("Данные") }
                Section {
                    Button("Очистить кабинет", role: .destructive) { deleting = true }.disabled(online.busy)
                }
            }.cabinetBackground().navigationTitle("Кабинет").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $addingService) { ServiceForm() }
                .sheet(item: $editService) { ServiceForm(service: $0) }
                .sheet(isPresented: $profile) { ProfileForm() }
                .sheet(isPresented: $authPresented) { AuthView() }
                .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Мой кабинет — \(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
                    if case .failure(let error) = result { backupError = error.localizedDescription }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get()
                        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 50_000_000 else { throw DataIssue.invalid("Максимальный размер копии — 50 МБ.") }
                        let bytes = try Data(contentsOf: url)
                        _ = try JSONDecoder().decode(CabinetData.self, from: bytes).validated()
                        pendingImport = bytes; confirmRestore = true
                    } catch { backupError = "Не удалось открыть копию: \(error.localizedDescription)" }
                }
                .confirmationDialog("Заменить текущие данные резервной копией? Все текущие записи будут заменены. Сначала сохраните копию, если хотите оставить их.", isPresented: $confirmRestore, titleVisibility: .visible) {
                    Button("Восстановить", role: .destructive) { if let bytes = pendingImport, store.restore(bytes) { notice = "Резервная копия восстановлена." }; pendingImport = nil }
                }
                .confirmationDialog("Удалить все локальные записи, клиентов и фотографии? Онлайн-кабинет очищается отдельно. Это действие необратимо.", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Удалить все локальные данные", role: .destructive) { online.disconnect(); if store.deleteAll() { notice = "Кабинет очищен." } }
                }
                .alert("Резервная копия", isPresented: Binding(get: { backupError != nil || notice != nil }, set: { if !$0 { backupError = nil; notice = nil } })) {
                    Button("Понятно") { backupError = nil; notice = nil }
                } message: { Text(backupError ?? notice ?? "") }.feedback()
        }
    }
}

struct ServiceForm: View {
    @EnvironmentObject var store: CabinetStore
    @Environment(\.dismiss) var dismiss
    var service: Service?
    @State private var name = ""
    @State private var minutes = 60
    @State private var price = ""
    @State private var initialized = false
    private var profession: ProfessionPreset { store.data.settings.professionPreset }
    var body: some View {
        NavigationStack {
            Form {
                Section(profession.serviceTitle) {
                    TextField("Название", text: $name)
                    Stepper("Длительность: \(minutes) мин", value: $minutes, in: 15...480, step: 15)
                    HStack { Text("Стоимость, ₽"); TextField("0", text: $price).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                }
                if let service {
                    Section {
                        Button(service.archived == true ? "Вернуть из архива" : "Убрать в архив", role: service.archived == true ? nil : .destructive) {
                            var edited = service; edited.archived = !(service.archived ?? false)
                            if store.saveService(edited) { dismiss() }
                        }
                    } footer: { Text("Услуга останется в истории, но исчезнет из списка для новых записей.") }
                }
            }.cabinetBackground().navigationTitle(service == nil ? "Новый \(profession.serviceTitle.lowercased())" : profession.serviceTitle).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Сохранить") {
                            guard let amount = Int(price) else { return }
                            if store.saveService(Service(id: service?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), minutes: minutes, price: amount, archived: service?.archived)) { dismiss() }
                        }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !(0...1_000_000).contains(Int(price) ?? -1))
                    }
                }.onAppear { guard !initialized else { return }; initialized = true; if let service { name = service.name; minutes = service.minutes; price = String(service.price) } }.feedback()
        }
    }
}

struct ProfileForm: View {
    @EnvironmentObject var store: CabinetStore
    @Environment(\.dismiss) var dismiss
    @State private var profile = Profile()
    @State private var initialized = false
    private var profession: ProfessionPreset { store.data.settings.professionPreset }
    private let days = [(2, "Пн"), (3, "Вт"), (4, "Ср"), (5, "Чт"), (6, "Пт"), (7, "Сб"), (1, "Вс")]
    var body: some View {
        NavigationStack {
            Form {
                Section("Профиль") {
                    TextField(profession == .tutor ? "Имя или название" : "Название кабинета", text: $profile.name)
                    TextField("Специализация", text: $profile.specialty)
                }
                Section("Рабочие часы") {
                    Picker("Начало дня", selection: $profile.openingHour) { ForEach(0..<24) { Text(String(format: "%02d:00", $0)).tag($0) } }
                    Picker("Конец дня", selection: $profile.closingHour) { ForEach(1..<25) { Text(String(format: "%02d:00", $0)).tag($0) } }
                    ForEach(days, id: \.0) { day in
                        Toggle(day.1, isOn: Binding(get: { profile.weekdays.contains(day.0) }, set: { on in if on { profile.weekdays.append(day.0) } else { profile.weekdays.removeAll { $0 == day.0 } } }))
                    }
                }
                Section {
                    Picker("Часовой пояс", selection: $profile.timezone) {
                        ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                    }
                } footer: { Text("По этим настройкам предлагаются свободные окна и открывается запись по ссылке. Вручную можно записать и вне рабочих часов.") }
            }.cabinetBackground().navigationTitle("Мой профиль").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { if store.saveProfile(profile) { dismiss() } }.disabled(profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || profile.openingHour >= profile.closingHour || profile.weekdays.isEmpty) }
                }.onAppear { if !initialized { profile = store.data.settings; initialized = true } }.feedback()
        }
    }
}

struct ReportsView: View {
    @EnvironmentObject var store: CabinetStore
    @State private var month = Date()
    private var paid: [Appointment] { store.data.appointments.filter { $0.status == .paid && store.calendar.isDate($0.start, equalTo: month, toGranularity: .month) } }
    private var sum: Int { paid.reduce(0) { $0 + $1.price } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Button { month = store.calendar.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Предыдущий месяц")
                    Spacer()
                    Text(month.ruFormatted(.dateTime.month(.wide).year(), in: store.calendar.timeZone).capitalized).font(.headline)
                    Spacer()
                    Button { month = store.calendar.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Следующий месяц")
                }
                VStack(alignment: .leading, spacing: 14) {
                    Eyebrow(text: "Оплаченные визиты")
                    Text(sum.rubles).font(.system(.largeTitle, design: .serif))
                    HStack { Text("\(paid.count) визитов"); Spacer(); Text("Средний чек: \((paid.isEmpty ? 0 : sum / paid.count).rubles)") }.font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).cardSurface()
                VStack(alignment: .leading, spacing: 20) {
                    Text("По услугам").font(.system(.title2, design: .serif))
                    let names = Set(paid.map(\.serviceName)).sorted()
                    if names.isEmpty { Text("Отмечайте оплату после визитов — здесь появятся итоги.").font(.callout).foregroundStyle(.secondary) }
                    ForEach(names, id: \.self) { name in
                        let amount = paid.filter { $0.serviceName == name }.reduce(0) { $0 + $1.price }
                        VStack(spacing: 9) {
                            HStack { Text(name); Spacer(); Text(amount.rubles) }.font(.subheadline)
                            GeometryReader { geo in Capsule().fill(Style.accent.opacity(0.14)).overlay(alignment: .leading) { Capsule().fill(Style.accent).frame(width: geo.size.width * (sum == 0 ? 0 : Double(amount) / Double(sum))) } }.frame(height: 5)
                        }
                    }
                }.cardSurface()
                Text("Суммы относятся к дате визита. Отметка «Оплачено» ведётся вручную и не принимает платежи.").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.background(Style.background).navigationTitle("Итоги").navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("На вашем устройстве") { Text("Имена, телефоны, заметки, фотографии и записи хранятся в файле приложения. Доступ к фото — только к выбранным вами изображениям. Приложение не содержит рекламы и сторонней аналитики.") }
            Section("Резервная копия") { Text("Экспорт содержит все данные кабинета, включая фотографии и телефоны. Сохраняйте файл там, где доступ есть только у вас. Восстановление заменяет текущие данные.") }
            Section("Онлайн-режим") { Text("При подключении онлайн-записи данные кабинета передаются на указанный вами сервер. На публичной странице видны только профиль, активные услуги и свободные часы. Контакты и заметки клиентов публично не показываются.") }
            Section("Аккаунт") { Text("При входе сервер получает подтверждённый идентификатор, имя и, если доступен, email от выбранного провайдера. Сессия на iPhone хранится в Keychain. Аккаунт используется для подключения своего кабинета на другом устройстве.") }
            Section("Системный календарь") { Text("После вашего разрешения приложение читает только название, календарь и время ближайших событий. Оно не меняет исходные события, не сохраняет участников и не создаёт для них отдельные уведомления.") }
            Section("Удаление") { Text("Аккаунт удаляется на экране «Аккаунт». Клиента можно удалить вместе с историей или очистить весь кабинет. Экспортированные копии удаляются отдельно в «Файлах», а онлайн-кабинет — в настройках онлайн-записи.") }
            Section("Уведомления") { Text("Напоминания приходят только мастеру на этот iPhone. Приложение не отправляет SMS или сообщения клиентам. Планируются ближайшие 60 уведомлений, список обновляется при открытии приложения и изменении записей.") }
        }.font(.callout).cabinetBackground().navigationTitle("Твои данные").navigationBarTitleDisplayMode(.inline)
    }
}
