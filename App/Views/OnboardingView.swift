import SwiftUI

/// Three steps: what it is, what it needs, and where to put it.
///
/// Permissions are asked for here and nowhere else — a request that arrives
/// with no explanation is the one people refuse.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0

    var body: some View {
        NavigationStack {
            TabView(selection: $step) {
                IntroPage().tag(0)
                PermissionsPage().tag(1)
                WidgetSetupView(isOnboarding: true) { finish() }.tag(2)
            }
            .tabViewStyle(.page)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step < 2 {
                        Button("onboarding.skip") { finish() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if step < 2 {
                        Button("onboarding.next") {
                            withAnimation { step += 1 }
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func finish() {
        SharedDefaults.onboardingComplete = true
        dismiss()
    }
}

private struct IntroPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("onboarding.intro.title")
                .font(.system(.largeTitle, design: .serif))
            Text("onboarding.intro.body")
                .font(.body)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                Bullet(symbol: "lock.display", text: "onboarding.intro.lockScreen")
                Bullet(symbol: "square.grid.2x2", text: "onboarding.intro.homeScreen")
                Bullet(symbol: "bell.badge", text: "onboarding.intro.alerts")
            }
            Spacer()
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PermissionsPage: View {
    @Environment(AppModel.self) private var model
    @State private var asked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("onboarding.permissions.title")
                .font(.system(.largeTitle, design: .serif))
            Text("onboarding.permissions.body")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Bullet(symbol: "bell", text: "onboarding.permissions.notifications")
                Bullet(symbol: "alarm", text: "onboarding.permissions.alarms")
            }

            Button {
                Task {
                    await model.requestPermissions()
                    asked = true
                }
            } label: {
                Text(asked ? "onboarding.permissions.asked" : "onboarding.permissions.ask")
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(asked)

            Text("onboarding.permissions.footer")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Also reachable from Settings, which is why it takes its own dismissal.
struct WidgetSetupView: View {
    @Environment(\.dismiss) private var dismiss
    var isOnboarding = false
    var onDone: (() -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("widgetSetup.title")
                        .font(.system(.largeTitle, design: .serif))
                    Text("widgetSetup.body")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 14) {
                        NumberedStep(number: 1, text: "widgetSetup.step1")
                        NumberedStep(number: 2, text: "widgetSetup.step2")
                        NumberedStep(number: 3, text: "widgetSetup.step3")
                        NumberedStep(number: 4, text: "widgetSetup.step4")
                    }

                    GroupBox {
                        Text("widgetSetup.why")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        onDone?() ?? dismiss()
                    } label: {
                        Text(isOnboarding ? "widgetSetup.finish" : "action.done")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isOnboarding {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("action.done") { dismiss() }
                    }
                }
            }
        }
    }
}

private struct NumberedStep: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.primary, in: .circle)
            Text(text)
                .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct Bullet: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Where the push endpoint is entered. Empty means push is off, which is the
/// default and a perfectly good way to run the app.
struct PushSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var endpoint = SharedDefaults.pushEndpoint ?? ""
    @State private var key = SharedDefaults.pushKey ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("settings.push.endpoint", text: $endpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("settings.push.key", text: $key)
                } footer: {
                    Text("settings.push.setup.footer")
                }

                Section {
                    Button("settings.push.clear", role: .destructive) {
                        endpoint = ""
                        key = ""
                    }
                }
            }
            .navigationTitle("settings.push.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") {
                        SharedDefaults.pushEndpoint = endpoint.trimmingCharacters(in: .whitespaces)
                        SharedDefaults.pushKey = key.trimmingCharacters(in: .whitespaces)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    PreviewHost { OnboardingView() }
}
