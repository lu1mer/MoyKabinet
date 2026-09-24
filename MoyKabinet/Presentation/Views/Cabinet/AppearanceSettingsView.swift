import SwiftUI

struct AppearanceSettingsView: View {
    @EnvironmentObject private var store: CabinetStore
    @Environment(\.dismiss) private var dismiss
    @State private var profession: ProfessionPreset = .beauty
    @State private var theme: AppTheme = .rose
    @State private var initialized = false
    @State private var saved = false

    var body: some View {
        ZStack {
            VibeBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Под твой формат")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .tracking(-1.3)
                        Text("Названия и стартовые услуги подстроятся, данные клиентов останутся на месте.")
                            .font(.subheadline)
                            .foregroundStyle(Style.muted)
                    }

                    VStack(alignment: .leading, spacing: 13) {
                        SectionHeading(title: "Направление")
                        ForEach(ProfessionPreset.allCases) { item in professionCard(item) }
                    }

                    VStack(alignment: .leading, spacing: 13) {
                        SectionHeading(title: "Дизайн")
                        HStack(spacing: 10) {
                            ForEach(AppTheme.allCases) { item in themeCard(item) }
                        }
                    }

                    PrimaryButton(title: "Применить стиль", icon: "sparkles") {
                        if store.applyAppearance(profession: profession, theme: theme) {
                            saved = true
                            ThemeController.shared.apply(theme)
                            dismiss()
                        }
                    }
                }
                .padding(22)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle("Вид приложения")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !initialized else { return }
            initialized = true
            profession = store.data.settings.professionPreset
            theme = store.data.settings.selectedTheme
        }
        .onDisappear {
            if !saved { ThemeController.shared.apply(store.data.settings.selectedTheme) }
        }
    }

    private func professionCard(_ item: ProfessionPreset) -> some View {
        let selected = profession == item
        return Button {
            withAnimation(.snappy) { profession = item }
        } label: {
            HStack(spacing: 15) {
                Image(systemName: item.icon)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 48, height: 48)
                    .foregroundStyle(selected ? .white : Style.accent)
                    .background(selected ? AnyShapeStyle(Style.gradient) : AnyShapeStyle(Style.accentSoft), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.headline)
                    Text(item == .tutor ? "Ученики, занятия и учебные форматы" : item == .beauty ? "Клиенты, процедуры и портфолио" : "Клиенты, встречи и консультации")
                        .font(.caption).foregroundStyle(Style.muted)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Style.accent : Style.line)
                    .font(.title3)
            }
            .padding(16)
            .contentShape(Rectangle())
            .vibeCard(radius: 20)
        }
        .buttonStyle(.plain)
    }

    private func themeCard(_ item: AppTheme) -> some View {
        let selected = theme == item
        let colors: [Color] = switch item {
        case .rose: [Color(red: 1, green: 0.30, blue: 0.60), Color(red: 0.78, green: 0.06, blue: 0.42)]
        case .graphite: [Color(red: 0.24, green: 0.70, blue: 0.92), Color(red: 0.04, green: 0.15, blue: 0.22)]
        case .indigo: [Color(red: 0.49, green: 0.43, blue: 1), Color(red: 0.20, green: 0.15, blue: 0.66)]
        }
        return Button {
            withAnimation(.snappy) {
                theme = item
                ThemeController.shared.apply(item)
            }
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                RoundedRectangle(cornerRadius: 15)
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 68)
                    .overlay(alignment: .topTrailing) {
                        if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white).padding(8) }
                    }
                Text(item.title).font(.subheadline.weight(.bold)).foregroundStyle(Style.ink)
                Text(item.subtitle).font(.system(size: 10)).foregroundStyle(Style.muted).lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Style.card, in: RoundedRectangle(cornerRadius: 19))
            .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(selected ? Style.accent : Style.line, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}
