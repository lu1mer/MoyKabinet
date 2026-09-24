import SwiftUI

struct CalendarIntegrationView: View {
    @EnvironmentObject private var store: CabinetStore
    @EnvironmentObject private var calendarImport: CalendarImportManager
    @State private var disconnecting = false

    var body: some View {
        ZStack {
            VibeBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    if calendarImport.hasFullAccess { connectedContent } else { connectCard }
                    privacyNote
                }
                .padding(22)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Системный календарь")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Что сделать с уже импортированными событиями?", isPresented: $disconnecting, titleVisibility: .visible) {
            Button("Оставить в расписании") { calendarImport.disconnect(removeImported: false, store: store) }
            Button("Удалить будущие события", role: .destructive) { calendarImport.disconnect(removeImported: true, store: store) }
            Button("Отмена", role: .cancel) { }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 28, weight: .semibold))
                Spacer()
                Text(calendarImport.enabled ? "ВКЛЮЧЕНО" : "КАЛЕНДАРЬ")
                    .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1.6)
            }
            Text("Свободное время без накладок")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("События выбранных календарей появятся в расписании и закроют время для онлайн-записи.")
                .font(.subheadline).opacity(0.82)
        }
        .foregroundStyle(.white)
        .padding(22)
        .background(Style.gradient, in: RoundedRectangle(cornerRadius: 25))
        .shadow(color: Style.accent.opacity(0.2), radius: 20, y: 10)
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Подключение займёт минуту").font(.headline)
            Text("iOS покажет системный запрос. Приложение читает только название и время событий; заметки и участники не сохраняются.")
                .font(.subheadline).foregroundStyle(Style.muted)
            PrimaryButton(title: calendarImport.busy ? "Подключаем…" : "Подключить календарь", icon: "calendar.badge.plus") {
                Task { await calendarImport.connect(store: store) }
            }
            .disabled(calendarImport.busy)
        }
        .padding(20)
        .vibeCard()
    }

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Автообновление").font(.headline)
                    Text("При каждом открытии приложения").font(.caption).foregroundStyle(Style.muted)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { calendarImport.enabled }, set: { calendarImport.setEnabled($0) }))
                    .labelsHidden()
            }
            .padding(18)
            .vibeCard(radius: 20)

            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Календари", detail: "\(calendarImport.selectedCalendarIDs.count)")
                ForEach(calendarImport.calendars, id: \.calendarIdentifier) { calendar in
                    Button {
                        let selected = calendarImport.selectedCalendarIDs.contains(calendar.calendarIdentifier)
                        calendarImport.setCalendar(calendar.calendarIdentifier, selected: !selected)
                    } label: {
                        HStack(spacing: 13) {
                            Circle().fill(Color(cgColor: calendar.cgColor)).frame(width: 12, height: 12)
                            Text(calendar.title).font(.body.weight(.medium)).foregroundStyle(Style.ink)
                            Spacer()
                            Image(systemName: calendarImport.selectedCalendarIDs.contains(calendar.calendarIdentifier) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(calendarImport.selectedCalendarIDs.contains(calendar.calendarIdentifier) ? Style.accent : Style.line)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                        .vibeCard(radius: 18)
                    }
                    .buttonStyle(.plain)
                }
            }

            PrimaryButton(title: calendarImport.busy ? "Обновляем…" : "Обновить сейчас", icon: "arrow.triangle.2.circlepath") {
                Task { await calendarImport.refresh(store) }
            }
            .disabled(calendarImport.busy || calendarImport.selectedCalendarIDs.isEmpty)

            if let message = calendarImport.message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Style.muted)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Style.accentSoft, in: RoundedRectangle(cornerRadius: 16))
            }

            Button("Отключить календарь", role: .destructive) { disconnecting = true }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
        }
    }

    private var privacyNote: some View {
        Label("Доступ можно отключить в любой момент. Исходные события в приложении «Календарь» никогда не изменяются.", systemImage: "hand.raised.fill")
            .font(.caption)
            .foregroundStyle(Style.muted)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .vibeCard(radius: 18)
    }
}
