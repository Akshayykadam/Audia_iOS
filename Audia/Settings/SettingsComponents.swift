//
//  SettingsComponents.swift
//  Audia
//

import SwiftUI

struct SettingsIconLabel: View {
    let title: String
    let icon: String
    var iconColor: Color = AudiaTheme.primary
    var textColor: Color = AudiaTheme.textPrimary

    var body: some View {
        Label {
            Text(LocalizedStringKey(title))
                .foregroundStyle(textColor)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
        }
        .font(.satoshi(size: 16, weight: .medium))
    }
}

struct SettingsNavigationRow<Destination: View>: View {
    @Environment(SettingsStore.self) private var settings
    let title: String
    let icon: String
    @ViewBuilder var destination: () -> Destination

    init(_ title: String, icon: String, @ViewBuilder destination: @escaping () -> Destination) {
        self.title = title
        self.icon = icon
        self.destination = destination
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            SettingsIconLabel(title: title, icon: icon)
        }
        .tint(AudiaTheme.primary)
    }
}

struct SettingsToggleRow: View {
    @Environment(SettingsStore.self) private var settings
    let title: String
    let icon: String?
    @Binding var isOn: Bool

    init(_ title: String, icon: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.icon = icon
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            if let icon {
                SettingsIconLabel(title: title, icon: icon)
            } else {
                Text(LocalizedStringKey(title))
                    .font(.satoshi(size: 16, weight: .medium))
                    .foregroundStyle(AudiaTheme.textPrimary)
            }
        }
        .toggleStyle(.amoled)
    }
}

struct SettingsPickerRow<T: SettingsOption>: View {
    @Environment(SettingsStore.self) private var settings
    let title: String
    let icon: String?
    @Binding var selection: T

    init(_ title: String, icon: String? = nil, selection: Binding<T>) {
        self.title = title
        self.icon = icon
        self._selection = selection
    }

    var body: some View {
        Picker(selection: $selection) {
            ForEach(Array(T.allCases)) { option in
                Text(LocalizedStringKey(option.displayName))
                    .font(.satoshi(size: 15, weight: .regular))
                    .tag(option)
            }
        } label: {
            if let icon {
                SettingsIconLabel(title: title, icon: icon)
            } else {
                Text(LocalizedStringKey(title))
                    .font(.satoshi(size: 16, weight: .medium))
                    .foregroundStyle(AudiaTheme.textPrimary)
            }
        }
        .font(.satoshi(size: 16, weight: .medium))
        .id(settings.accentName)
        .tint(AudiaTheme.primary)
    }
}

struct SettingsStepperRow: View {
    let title: String
    let icon: String?
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    @Binding var value: Double

    init(_ title: String,
         icon: String? = nil,
         value: Binding<Double>,
         in range: ClosedRange<Double> = 0.5...2.0,
         step: Double = 0.1,
         format: @escaping (Double) -> String = { String(format: "%.1fx", $0) }) {
        self.title = title
        self.icon = icon
        self._value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        Stepper {
            if let icon {
                SettingsIconLabel(title: title, icon: icon)
                    .overlay(alignment: .trailing) {
                        Text(": \(format(value))")
                            .font(.satoshi(size: 15, weight: .regular))
                    }
            } else {
                HStack(spacing: 0) {
                    Text(LocalizedStringKey(title))
                        .font(.satoshi(size: 16, weight: .medium))
                        .foregroundStyle(AudiaTheme.textPrimary)
                    Text(": \(format(value))")
                        .font(.satoshi(size: 15, weight: .regular))
                }
            }
        } onIncrement: {
            value = min(value + step, range.upperBound)
        } onDecrement: {
            value = max(value - step, range.lowerBound)
        }
    }
}

struct SettingsLinkRow: View {
    let title: String
    let icon: String
    let url: URL

    init(_ title: String, icon: String, url: URL) {
        self.title = title
        self.icon = icon
        self.url = url
    }

    var body: some View {
        Link(destination: url) {
            SettingsIconLabel(title: title, icon: icon, textColor: AudiaTheme.primary)
        }
    }
}
