import SwiftUI

@main
struct MoyKabinetApp: App {
    @StateObject private var store = CabinetStore()
    @StateObject private var online = OnlineManager()
    @StateObject private var auth = AuthViewModel()
    @StateObject private var calendarImport = CalendarImportManager()
    @StateObject private var themeController = ThemeController.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(online)
                .environmentObject(auth)
                .environmentObject(calendarImport)
                .tint(Style.accent)
                .preferredColorScheme(themeController.theme.preferredColorScheme)
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .environment(\.calendar, store.calendar)
                .environment(\.timeZone, TimeZone(identifier: store.data.settings.timezone) ?? .current)
                .onAppear { themeController.apply(store.data.settings.selectedTheme) }
                .onReceive(store.$data.dropFirst()) { value in
                    themeController.apply(value.settings.selectedTheme)
                    online.schedule(store)
                }
                .task {
                    while !Task.isCancelled {
                        await online.sync(store)
                        do { try await Task.sleep(for: .seconds(30)) } catch { break }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.scheduleReminders()
                        Task {
                            await auth.bootstrap()
                            await online.sync(store)
                            if !ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                                await calendarImport.refresh(store)
                            }
                        }
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingLaunch = true
    private var bypassAuthentication: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") }

    var body: some View {
        ZStack {
            if auth.isSignedIn || bypassAuthentication {
                TabView {
                    DayView(isCalendar: false).tabItem { Label("Сегодня", systemImage: "house.fill") }
                    DayView(isCalendar: true).tabItem { Label("Календарь", systemImage: "calendar") }
                    ClientsView().tabItem { Label("Клиенты", systemImage: "person.2") }
                    CabinetView().tabItem { Label("Кабинет", systemImage: "square.grid.2x2") }
                }
                .foregroundStyle(Style.ink)
                .toolbarBackground(Style.card.opacity(0.96), for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .accessibilityHidden(showingLaunch)
            } else {
                AuthView(canDismiss: false)
            }

            if showingLaunch {
                LaunchView()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    .zIndex(1)
            }
        }
        .task {
            await auth.bootstrap()
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.12 : 0.88))
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.32)) { showingLaunch = false }
        }
    }
}
