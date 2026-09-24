import SwiftUI
import PhotosUI

struct ClientsView: View {
    @EnvironmentObject var store: CabinetStore
    @State private var query = ""
    @State private var adding = false
    @State private var archived = false
    @State private var bookingClient: Client?
    private var model: ClientsViewModel { ClientsViewModel(data: store.data, query: query, showArchived: archived) }
    private var clients: [Client] { model.clients }
    private var profession: ProfessionPreset { store.data.settings.professionPreset }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Eyebrow(text: archived ? "В АРХИВЕ" : profession.clientsTitle)
                        Spacer(); Text("\(clients.count)").font(.system(.title2, design: .serif)).foregroundStyle(Style.accent)
                    }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 14, trailing: 0))
                }
                Section {
                    ForEach(clients) { client in
                        NavigationLink { ClientDetailView(clientID: client.id) } label: {
                            HStack(spacing: 14) {
                                ClientAvatar(client: client)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(client.name).font(.body.weight(.medium))
                                    if let visit = nextVisit(for: client) {
                                        Text("Ближайшая · \(visit.start.ruFormatted(.dateTime.day().month(.abbreviated).hour().minute(), in: store.calendar.timeZone))")
                                            .font(.caption).foregroundStyle(Style.accent)
                                    } else if !client.phone.isEmpty {
                                        Text(client.phone).font(.caption).foregroundStyle(Style.muted)
                                    }
                                }.padding(.vertical, 8)
                            }
                        }
                        .listRowBackground(Style.card)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if client.archived != true {
                                Button { bookingClient = client } label: { Label("Записать", systemImage: "calendar.badge.plus") }
                                    .tint(Style.accent)
                            }
                        }
                    }
                }
            }.cabinetBackground()
                .overlay {
                    if clients.isEmpty {
                        ContentUnavailableView(query.isEmpty ? (archived ? "Архив пуст" : "Пока пусто") : "Никого не нашли", systemImage: "person.2", description: Text(query.isEmpty ? "Добавьте первую карточку." : "Попробуйте другое имя."))
                    }
                }
                .searchable(text: $query, prompt: "Имя или телефон")
                .navigationTitle(profession.clientsTitle)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button { archived.toggle() } label: { Image(systemName: archived ? "person.2" : "archivebox") }.accessibilityLabel(archived ? "Активные клиенты" : "Архив клиентов") }
                    ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Добавить клиента") }
                }
                .sheet(isPresented: $adding) { ClientForm().presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
                .sheet(item: $bookingClient) { client in
                    BookingForm(date: .now, clientID: client.id)
                        .presentationDragIndicator(.visible)
                }
                .feedback()
        }
    }

    private func nextVisit(for client: Client) -> Appointment? {
        store.data.appointments
            .filter { $0.clientID == client.id && $0.status == .planned && $0.start > .now }
            .min { $0.start < $1.start }
    }
}

struct ClientDetailView: View {
    @EnvironmentObject var store: CabinetStore
    @Environment(\.dismiss) var dismiss
    let clientID: UUID
    @State private var editing = false
    @State private var booking = false
    @State private var deleting = false
    private var profession: ProfessionPreset { store.data.settings.professionPreset }
    var body: some View {
        if let client = store.client(clientID) {
            List {
                Section {
                    VStack(spacing: 14) {
                        ClientAvatar(client: client, size: 82)
                        Text(client.name).font(.system(.title, design: .serif)).multilineTextAlignment(.center)
                        if !client.phone.isEmpty {
                            if let url = URL(string: "tel:\(client.phone.filter { $0.isNumber || $0 == "+" })") { Link(client.phone, destination: url).font(.subheadline) }
                        }
                        if client.archived == true { Label("В архиве", systemImage: "archivebox").font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity).padding(.vertical, 18).listRowBackground(Color.clear)
                }
                if client.archived != true { Section { Button { booking = true } label: { Label(profession == .tutor ? "Записать на занятие" : "Записать на визит", systemImage: "calendar.badge.plus") } } }
                if client.telegramURL != nil || client.emailURL != nil || client.websiteURL != nil {
                    Section("Связаться") {
                        if let url = client.telegramURL {
                            Link(destination: url) {
                                Label(client.telegramDisplay, systemImage: "paperplane.fill")
                            }
                        }
                        if let url = client.emailURL, let email = client.email {
                            Link(destination: url) { Label(email, systemImage: "envelope.fill") }
                        }
                        if let url = client.websiteURL {
                            Link(destination: url) {
                                Label(client.link ?? "Открыть ссылку", systemImage: "link")
                            }
                        }
                    }
                }
                Section("Пожелания") { Text(client.notes.isEmpty ? "—" : client.notes).font(.callout).foregroundStyle(client.notes.isEmpty ? .secondary : .primary) }
                if let photos = client.photos, !photos.isEmpty {
                    Section("Работы и идеи") {
                        ScrollView(.horizontal) {
                            HStack(spacing: 12) {
                                ForEach(Array(photos.enumerated()), id: \.offset) { _, bytes in
                                    if let image = UIImage(data: bytes) { Image(uiImage: image).resizable().scaledToFill().frame(width: 160, height: 190).clipped().clipShape(RoundedRectangle(cornerRadius: 16)) }
                                }
                            }.padding(.vertical, 6)
                        }
                    }
                }
                Section("История") {
                    let visits = store.data.appointments.filter { $0.clientID == clientID }.sorted { $0.start > $1.start }
                    if visits.isEmpty { Text("Пока без записей").font(.callout).foregroundStyle(.secondary) }
                    ForEach(visits) { visit in
                        NavigationLink { VisitDetailView(visitID: visit.id) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(visit.serviceName)
                                Text(visit.start.ruFormatted(Date.FormatStyle(date: .abbreviated, time: .shortened), in: store.calendar.timeZone)).font(.caption).foregroundStyle(.secondary)
                                Text("\(visit.status.rawValue) · \(visit.price.rubles)").font(.caption).foregroundStyle(Style.accent)
                            }.padding(.vertical, 5)
                        }
                    }
                }
                Section {
                    Button(client.archived == true ? "Вернуть из архива" : "Переместить в архив") { if store.archiveClient(client) { dismiss() } }
                    Button("Удалить клиента и историю", role: .destructive) { deleting = true }
                }
            }.cabinetBackground().navigationTitle(profession.clientTitle).navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Изменить") { editing = true } }
                .sheet(isPresented: $editing) { ClientForm(client: client).presentationDetents([.large]).presentationDragIndicator(.visible) }
                .sheet(isPresented: $booking) { BookingForm(date: .now, clientID: client.id) }
                .confirmationDialog("Удалить клиента, фотографии и все его записи? Это изменит суммы дохода. Действие необратимо.", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Удалить все данные клиента", role: .destructive) { if store.deleteClient(clientID) { dismiss() } }
                }.feedback()
        }
    }
}

private extension Client {
    var telegramDisplay: String {
        let value = (telegram ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("@") { return value }
        if let last = value.split(separator: "/").last, value.contains("t.me") { return "@\(last)" }
        return value.isEmpty ? "Telegram" : "@\(value)"
    }

    var telegramURL: URL? {
        var value = (telegram ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let url = URL(string: value), url.scheme != nil {
            guard url.scheme?.lowercased() == "https",
                  ["t.me", "telegram.me"].contains(url.host?.lowercased() ?? "") else { return nil }
            return url
        }
        value = value.replacingOccurrences(of: "@", with: "")
        if value.hasPrefix("t.me/") { value = String(value.dropFirst(5)) }
        guard value.range(of: "^[A-Za-z0-9_]{5,32}$", options: .regularExpression) != nil else { return nil }
        return URL(string: "https://t.me/\(value)")
    }

    var emailURL: URL? {
        let value = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.contains("@"), let escaped = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "mailto:\(escaped)")
    }

    var websiteURL: URL? {
        let value = (link ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let url = URL(string: value)?.scheme == nil ? URL(string: "https://\(value)") : URL(string: value)
        guard url?.scheme?.lowercased() == "https", url?.host?.isEmpty == false else { return nil }
        return url
    }
}

struct ClientForm: View {
    @EnvironmentObject private var store: CabinetStore
    @Environment(\.dismiss) private var dismiss
    var client: Client?
    var onSave: ((UUID) -> Void)?
    @State private var name = ""
    @State private var phone = ""
    @State private var telegram = ""
    @State private var email = ""
    @State private var link = ""
    @State private var notes = ""
    @State private var photos: [Data] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var loadingPhotos = false
    @State private var showMore = false
    @State private var initialized = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, phone, telegram, email, link, notes }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !loadingPhotos }
    private var profession: ProfessionPreset { store.data.settings.professionPreset }

    var body: some View {
        NavigationStack {
            ZStack {
                VibeBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        identityCard
                        moreCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: client == nil ? "Добавить и выбрать" : "Сохранить", icon: "checkmark") {
                    save()
                }
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.42)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(.ultraThinMaterial)
                .accessibilityIdentifier("saveClient")
            }
            .navigationTitle(client == nil ? "Новый \(profession.clientTitle.lowercased())" : "Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
            .onAppear { initialize() }
            .onChange(of: selectedPhotos) { _, items in load(items) }
            .feedback()
        }
    }

    private var identityCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: "person.fill")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 42, height: 42)
                    .foregroundStyle(Style.accent)
                    .background(Style.accentSoft, in: Circle())
                TextField(profession == .tutor ? "Имя ученика" : "Имя клиента", text: $name)
                    .textContentType(.name)
                    .font(.body.weight(.semibold))
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .phone }
                    .accessibilityIdentifier("clientName")
            }
            .padding(17)

            Divider().overlay(Style.line).padding(.leading, 72)

            HStack(spacing: 13) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 42, height: 42)
                    .foregroundStyle(Style.accent)
                    .background(Style.accentSoft, in: Circle())
                TextField("Telegram — @username", text: $telegram)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($focusedField, equals: .telegram)
            }
            .padding(17)

            Divider().overlay(Style.line).padding(.leading, 72)

            HStack(spacing: 13) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 42, height: 42)
                    .foregroundStyle(Style.accent)
                    .background(Style.accentSoft, in: Circle())
                TextField("Телефон — необязательно", text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .focused($focusedField, equals: .phone)
            }
            .padding(17)
        }
        .vibeCard()
    }

    private var moreCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) { showMore.toggle() }
            } label: {
                HStack(spacing: 13) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 42, height: 42)
                        .foregroundStyle(Style.accent)
                        .background(Style.accentSoft, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Дополнительно").font(.body.weight(.semibold))
                        Text(extraSummary).font(.caption).foregroundStyle(Style.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Style.muted)
                        .rotationEffect(.degrees(showMore ? 180 : 0))
                }
                .padding(17)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showMore {
                Divider().overlay(Style.line).padding(.leading, 20)

                VStack(alignment: .leading, spacing: 13) {
                    Label("Другие контакты", systemImage: "link")
                        .font(.subheadline.weight(.semibold))
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .focused($focusedField, equals: .email)
                        .padding(14)
                        .background(Style.accentSoft.opacity(0.52), in: RoundedRectangle(cornerRadius: 15))
                    TextField("Сайт или другая ссылка", text: $link)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .focused($focusedField, equals: .link)
                        .padding(14)
                        .background(Style.accentSoft.opacity(0.52), in: RoundedRectangle(cornerRadius: 15))
                }
                .padding(18)

                Divider().overlay(Style.line).padding(.horizontal, 18)

                VStack(alignment: .leading, spacing: 12) {
                    Label("Заметка", systemImage: "text.alignleft")
                        .font(.subheadline.weight(.semibold))
                    TextField("Предпочтения, оттенки, важные детали…", text: $notes, axis: .vertical)
                        .lineLimit(3...7)
                        .focused($focusedField, equals: .notes)
                        .padding(14)
                        .background(Style.accentSoft.opacity(0.52), in: RoundedRectangle(cornerRadius: 15))
                }
                .padding(18)

                Divider().overlay(Style.line).padding(.horizontal, 18)

                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Label("Фото", systemImage: "photo.on.rectangle.angled")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(photos.count)/8").font(.caption).foregroundStyle(Style.muted)
                    }

                    if !photos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(photos.enumerated()), id: \.offset) { index, bytes in
                                    if let image = UIImage(data: bytes) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 92, height: 110)
                                            .clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: 15))
                                            .overlay(alignment: .topTrailing) {
                                                Button { photos.remove(at: index) } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.title3)
                                                        .foregroundStyle(.white, .black.opacity(0.55))
                                                        .padding(5)
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityLabel("Удалить фото \(index + 1)")
                                            }
                                    }
                                }
                            }
                        }
                        .scrollClipDisabled()
                    }

                    if photos.count < 8 {
                        PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 8 - photos.count, matching: .images) {
                            Label("Добавить фото", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Style.accent)
                                .padding(.horizontal, 15)
                                .frame(height: 42)
                                .background(Style.accentSoft, in: Capsule())
                        }
                        .disabled(loadingPhotos)
                    }
                    if loadingPhotos { ProgressView("Обрабатываем фото…").font(.caption) }
                }
                .padding(18)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .vibeCard()
    }

    private var extraSummary: String {
        if notes.isEmpty && photos.isEmpty && email.isEmpty && link.isEmpty { return "Контакты, заметка и фотографии" }
        var values: [String] = []
        if !email.isEmpty || !link.isEmpty { values.append("есть контакты") }
        if !notes.isEmpty { values.append("есть заметка") }
        if !photos.isEmpty { values.append("фото: \(photos.count)") }
        return values.joined(separator: " · ")
    }

    private func initialize() {
        guard !initialized else { return }
        initialized = true
        if let client {
            name = client.name
            phone = client.phone
            telegram = client.telegram ?? ""
            email = client.email ?? ""
            link = client.link ?? ""
            notes = client.notes
            photos = client.photos ?? []
            showMore = !notes.isEmpty || !photos.isEmpty || !email.isEmpty || !link.isEmpty
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focusedField = .name }
        }
    }

    private func save() {
        let item = Client(
            id: client?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes,
            archived: client?.archived,
            photos: photos,
            telegram: telegram.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            link: link.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if store.saveClient(item) { onSave?(item.id); dismiss() }
    }

    private func load(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        loadingPhotos = true
        Task {
            for item in items {
                if let bytes = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: bytes), photos.count < 8 {
                    let factor = min(1, 1200 / max(image.size.width, image.size.height))
                    let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
                    let format = UIGraphicsImageRendererFormat(); format.scale = 1
                    let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                        image.draw(in: CGRect(origin: .zero, size: size))
                    }
                    if let jpeg = resized.jpegData(compressionQuality: 0.65), jpeg.count <= 1_000_000 {
                        photos.append(jpeg)
                    } else {
                        store.error = "Фотография слишком большая. Выберите другое изображение."
                    }
                } else {
                    store.error = "Не удалось загрузить фотографию."
                }
            }
            loadingPhotos = false
            selectedPhotos = []
        }
    }
}
