import SwiftUI

struct AuthView: View {
    let canDismiss: Bool
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var store: CabinetStore
    @EnvironmentObject var online: OnlineManager
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDeletion = false
    @State private var creatingAccount = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var resetCode = ""
    @State private var newPassword = ""

    init(canDismiss: Bool = true) { self.canDismiss = canDismiss }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("м.")
                            .font(.system(size: 64, weight: .black, design: .rounded))
                            .tracking(-6)
                            .foregroundStyle(Style.gradient)
                        Text(auth.session == nil ? "Вход в кабинет" : "Твой аккаунт")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .tracking(-1.2)
                        Text(auth.session == nil
                             ? "Войди, чтобы открыть свой кабинет на другом устройстве."
                             : "Управляй входом и подключёнными кабинетами.")
                            .font(.callout)
                            .foregroundStyle(Style.muted)
                    }

                    if let session = auth.session {
                        AccountCard(user: session.user)
                        if auth.offlineSession {
                            Label("Офлайн: записи доступны, вход обновится при подключении", systemImage: "wifi.slash")
                                .font(.caption).foregroundStyle(Style.muted)
                        }

                        if let credentials = online.credentials {
                            let linked = auth.cabinets.contains { $0.id == credentials.id }
                            if linked {
                                Label("Онлайн-кабинет связан с аккаунтом", systemImage: "checkmark.circle.fill")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Style.accent)
                            } else {
                                Button {
                                    Task { await auth.link(credentials) }
                                } label: {
                                    Label("Связать онлайн-кабинет", systemImage: "link")
                                }
                                .disabled(auth.accountBusy)
                            }
                        } else if !auth.cabinets.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Твои кабинеты")
                                    .font(.system(size: 21, weight: .bold, design: .rounded))
                                ForEach(auth.cabinets) { cabinet in
                                    Button {
                                        Task { await auth.connect(cabinet, store: store, online: online) }
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(cabinet.name).font(.headline)
                                                if let specialty = cabinet.specialty {
                                                    Text(specialty).font(.caption).foregroundStyle(Style.muted)
                                                }
                                            }
                                            Spacer()
                                            Image(systemName: "arrow.down.circle")
                                        }
                                        .foregroundStyle(Style.ink)
                                        .padding(18)
                                        .background(Style.card, in: RoundedRectangle(cornerRadius: 18))
                                    }
                                    .disabled(auth.accountBusy || !store.data.clients.isEmpty || !store.data.appointments.isEmpty)
                                }
                                if !store.data.clients.isEmpty || !store.data.appointments.isEmpty {
                                    Text("Чтобы загрузить кабинет с другого устройства, сначала сохрани копию и очисти текущий кабинет.")
                                        .font(.caption)
                                        .foregroundStyle(Style.muted)
                                }
                            }
                        } else {
                            NavigationLink {
                                OnlineView()
                            } label: {
                                Label("Настроить онлайн-запись", systemImage: "link")
                            }
                        }

                        Button("Выйти из аккаунта", role: .destructive) { Task { await auth.signOut() } }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                        Button("Удалить аккаунт", role: .destructive) { confirmingDeletion = true }
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .disabled(auth.accountBusy)
                    } else {
                        if let verificationEmail = auth.verificationEmail {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Код отправлен на \(verificationEmail)")
                                    .font(.subheadline)
                                    .foregroundStyle(Style.muted)
                                TextField("6 цифр", text: $code)
                                    .keyboardType(.numberPad)
                                    .textContentType(.oneTimeCode)
                                    .textFieldStyle(.plain).authFieldStyle()
                                    .accessibilityIdentifier("verificationCode")
                                Button("Подтвердить email") { Task { await auth.confirm(code: code) } }
                                    .buttonStyle(.borderedProminent)
                                    .frame(maxWidth: .infinity)
                                    .disabled(code.count != 6 || auth.busy)
                            }
                        } else if let resetEmail = auth.passwordResetEmail {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Код восстановления отправлен на \(resetEmail)")
                                    .font(.subheadline).foregroundStyle(Style.muted)
                                TextField("6 цифр", text: $resetCode)
                                    .keyboardType(.numberPad).textContentType(.oneTimeCode).textFieldStyle(.plain).authFieldStyle()
                                SecureField("Новый пароль", text: $newPassword)
                                    .textContentType(.newPassword).textFieldStyle(.plain).authFieldStyle()
                                Button("Сохранить новый пароль") { Task { await auth.resetPassword(code: resetCode, newPassword: newPassword) } }
                                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                                    .disabled(resetCode.count != 6 || newPassword.isEmpty || auth.busy)
                            }
                        } else {
                            VStack(spacing: 12) {
                                if creatingAccount {
                                    TextField("Имя", text: $name)
                                        .textContentType(.name)
                                        .textFieldStyle(.plain).authFieldStyle()
                                }
                                TextField("Email", text: $email)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.emailAddress)
                                    .textContentType(.emailAddress)
                                    .textFieldStyle(.plain).authFieldStyle()
                                    .accessibilityIdentifier("authEmail")
                                SecureField("Пароль", text: $password)
                                    .textContentType(creatingAccount ? .newPassword : .password)
                                    .textFieldStyle(.plain).authFieldStyle()
                                    .accessibilityIdentifier("authPassword")
                                Button(creatingAccount ? "Создать аккаунт" : "Войти") {
                                    Task {
                                        if creatingAccount { await auth.register(name: name, email: email, password: password) }
                                        else { await auth.login(email: email, password: password) }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .frame(maxWidth: .infinity)
                                .disabled(!auth.canSignIn(with: .email) || email.isEmpty || password.isEmpty || (creatingAccount && name.isEmpty) || auth.busy)
                                Button(creatingAccount ? "У меня уже есть аккаунт" : "Создать аккаунт") { creatingAccount.toggle() }
                                    .font(.subheadline.weight(.semibold))
                                if !creatingAccount {
                                    Button("Не помню пароль") { Task { await auth.requestPasswordReset(email: email) } }
                                        .font(.caption.weight(.semibold))
                                        .disabled(email.isEmpty || auth.busy)
                                }
                            }

                            HStack { Rectangle().frame(height: 1); Text("или").font(.caption); Rectangle().frame(height: 1) }
                                .foregroundStyle(Style.line)

                            VStack(spacing: 12) {
                            ForEach(AuthProvider.allCases.filter { $0 != .email }) { provider in
                                Button { Task { await auth.signIn(provider) } } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: provider.systemImage)
                                            .font(.system(size: 21, weight: .semibold))
                                            .frame(width: 28)
                                        Text("Продолжить через \(provider.title)")
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        Spacer()
                                        if auth.providerInFlight == provider {
                                            ProgressView().tint(Style.accent)
                                        } else {
                                            Image(systemName: "arrow.up.right")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(Style.muted)
                                        }
                                    }
                                    .foregroundStyle(Style.ink)
                                    .padding(.horizontal, 18)
                                    .frame(height: 58)
                                    .background(Style.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Style.line, lineWidth: 1))
                                }
                                .disabled(auth.busy || !auth.canSignIn(with: provider))
                                .accessibilityValue(auth.providerInFlight == provider ? "Выполняется вход" : (auth.canSignIn(with: provider) ? "Доступно" : "Недоступно"))
                                .accessibilityHint(auth.canSignIn(with: provider) ? "Открыть вход через \(provider.title)" : "Провайдер пока не настроен")
                            }
                        }
                        }
                        if !AuthProvider.allCases.contains(where: { auth.canSignIn(with: $0) }) {
                            Text(auth.checkingProviders ? "Проверяем способы входа…" : (auth.providerCheckFailed ? "Не удалось связаться с сервером входа." : "Вход появится после подключения сервера."))
                                .font(.caption)
                                .foregroundStyle(Style.muted)
                        }
                    }
                }
                .padding(24)
            }
            .cabinetBackground()
            .navigationTitle("Аккаунт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canDismiss {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Закрыть") { dismiss() }
                    }
                }
            }
            .alert("Ошибка аккаунта", isPresented: Binding(
                get: { auth.error != nil },
                set: { if !$0 { auth.error = nil } }
            )) {
                Button("Понятно", role: .cancel) { auth.error = nil }
            } message: {
                Text(auth.error ?? "")
            }
            .confirmationDialog(
                "Удалить аккаунт и все связанные с ним данные входа? Локальные записи останутся на устройстве. Онлайн-кабинет удаляется отдельно в настройках онлайн-записи.",
                isPresented: $confirmingDeletion,
                titleVisibility: .visible
            ) {
                Button("Удалить аккаунт", role: .destructive) {
                    Task { await auth.deleteAccount() }
                }
            }
            .task {
                await auth.refreshProviderAvailability()
                if auth.isSignedIn { await auth.refreshCabinets() }
            }
        }
    }
}

private struct AccountCard: View {
    let user: AuthUser

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(Style.accentSoft)
                Text(String((user.displayName ?? user.email ?? user.provider.title).prefix(1)).uppercased())
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Style.accent)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 5) {
                Text(user.displayName ?? user.email ?? user.provider.title)
                    .font(.headline)
                if let email = user.email, !email.isEmpty {
                    Text(email).font(.caption).foregroundStyle(Style.muted)
                }
                Text("Через \(user.provider.title)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Style.accent)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Style.accent)
        }
        .padding(18)
        .background(Style.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Style.line, lineWidth: 1))
    }
}

private extension View {
    func authFieldStyle() -> some View {
        self
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(Style.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Style.line, lineWidth: 1))
    }
}
