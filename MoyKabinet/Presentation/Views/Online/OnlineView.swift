import SwiftUI

struct OnlineView: View {
    @EnvironmentObject var store: CabinetStore
    @EnvironmentObject var online: OnlineManager
    @EnvironmentObject var auth: AuthViewModel
    @State private var server = ""
    @State private var id = ""
    @State private var key = ""
    @State private var existing = false
    @State private var showKey = false
    @State private var replace = false
    @State private var delete = false
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "link").font(.title).foregroundStyle(Style.accent)
                    Text("Запись по ссылке.").font(.system(size: 27, weight: .bold, design: .rounded))
                    Text("Клиент выбирает время. Ты видишь запись.").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 12)
            }
            if let c = online.credentials {
                Section("Твоя ссылка") {
                    if let url = online.publicURL { ShareLink(item: url) { Label("Поделиться ссылкой", systemImage: "square.and.arrow.up") }; Link("Открыть страницу записи", destination: url) }
                    Button { Task { await online.sync(store) } } label: { Label(online.busy ? "Синхронизируем…" : "Синхронизировать сейчас", systemImage: "arrow.triangle.2.circlepath") }.disabled(online.busy)
                    if let last = online.lastSync { Text("Последняя синхронизация: \(last.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                }
                Section {
                    DisclosureGroup("Доступ на другом устройстве", isExpanded: $showKey) {
                        LabeledContent("Сервер", value: c.server).textSelection(.enabled)
                        Text("ID: \(c.id)").font(.caption.monospaced()).textSelection(.enabled)
                        Text(c.ownerKey).font(.caption.monospaced()).textSelection(.enabled).privacySensitive()
                        Text("Ключ даёт полный доступ к кабинету. Сохраните его в менеджере паролей. Клиентам отправляйте только ссылку.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Загрузить версию сервера") { replace = true }.disabled(online.busy)
                    Button("Отключить синхронизацию") { online.disconnect() }.disabled(online.busy)
                    Button("Удалить онлайн-кабинет", role: .destructive) { delete = true }.disabled(online.busy)
                } footer: { Text("Изменения синхронизируются при открытом приложении.") }
            } else {
                Section {
                    TextField("https://booking.example.com", text: $server).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Toggle("У меня уже есть онлайн-кабинет", isOn: $existing)
                    if existing {
                        TextField("Идентификатор кабинета", text: $id).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Ключ доступа", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Button(existing ? "Подключить кабинет" : "Включить онлайн-запись") {
                        Task { if existing { await online.connect(server: server, id: id, key: key, store: store) } else { await online.create(server: server, store: store, accessToken: auth.session?.accessToken) } }
                    }.disabled(server.isEmpty || online.busy)
                } header: { Text("Подключение") } footer: { Text("Укажите адрес сервера для онлайн-записи. Данные кабинета будут переданы на него.") }
            }
            if online.busy { Section { ProgressView("Подождите…") } }
            if let message = online.message { Section { Text(message).font(.callout).foregroundStyle(online.failed ? .orange : Style.accent) } }
        }.cabinetBackground().navigationTitle("Онлайн-запись").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Заменить локальные данные данными сервера? Сначала сохраните резервную копию в разделе «Кабинет».", isPresented: $replace, titleVisibility: .visible) {
                Button("Загрузить версию сервера", role: .destructive) { Task { await online.useServer(store) } }
            }
            .confirmationDialog("Удалить серверные данные и выключить ссылку для клиентов? Локальные данные останутся на iPhone.", isPresented: $delete, titleVisibility: .visible) {
                Button("Удалить онлайн-кабинет", role: .destructive) { Task { await online.deleteRemote() } }
            }.feedback()
    }
}
