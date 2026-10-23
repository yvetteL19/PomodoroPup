import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var vm: DogViewModel
    @EnvironmentObject var notificationService: NotificationService
    @Binding var showOnboarding: Bool
    @Environment(\.dismissWindow) private var dismissWindow
    var isWindow: Bool = false
    var onComplete: (() -> Void)? = nil
    @State private var selectedMinutes = 25

    var body: some View {
        VStack(spacing: 20) {
            Image("dog_work").resizable().scaledToFit().frame(width: 120, height: 120)
                .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(NSLocalizedString("onboarding.welcome.title", comment: ""))
                    .font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text(NSLocalizedString("onboarding.welcome.subtitle", comment: ""))
                    .foregroundStyle(.secondary)
            }.multilineTextAlignment(.center)
            Label(NSLocalizedString("onboarding.menu_bar", comment: ""), systemImage: "menubar.rectangle")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("onboarding.duration", comment: "")).font(.headline)
                Picker(NSLocalizedString("onboarding.duration", comment: ""), selection: $selectedMinutes) {
                    ForEach([10, 25, 45], id: \.self) { minutes in
                        Text(String(format: NSLocalizedString("onboarding.minutes", comment: ""), minutes)).tag(minutes)
                    }
                }.pickerStyle(.segmented).labelsHidden()
            }.disabled(vm.storageError != nil)

            VStack(alignment: .leading, spacing: 8) {
                Label(NSLocalizedString("onboarding.notification_optional", comment: ""), systemImage: "bell")
                    .font(.callout).foregroundStyle(.secondary)
                if notificationService.status == .allowed {
                    Label(NSLocalizedString("notification.status_allowed", comment: ""), systemImage: "checkmark.circle")
                        .font(.callout).foregroundStyle(.secondary)
                } else if notificationService.status == .requesting {
                    ProgressView().controlSize(.small)
                } else if notificationService.status == .denied || notificationService.status == .alertsDisabled {
                    Text(NSLocalizedString("onboarding.notification_later", comment: ""))
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Button(NSLocalizedString("onboarding.enable", comment: "")) {
                        Task { await notificationService.requestPermission() }
                    }
                }
                if let error = notificationService.errorMessage {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)

            if let error = vm.storageError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            Button(String(format: NSLocalizedString("onboarding.start", comment: ""), selectedMinutes)) {
                guard vm.timerState == .stopped else {
                    completeOnboarding()
                    return
                }
                vm.workDuration = Double(selectedMinutes) * 60
                guard vm.storageError == nil else { return }
                vm.startTimer()
                if vm.isTimerRunning { completeOnboarding() }
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .keyboardShortcut(.defaultAction).disabled(vm.storageError != nil)
            Button(NSLocalizedString("onboarding.start_later", comment: "")) { completeOnboarding() }
                .buttonStyle(.borderless).keyboardShortcut(.cancelAction)
        }
        .padding(28).frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await notificationService.refresh() }
        .onChange(of: vm.timerState) { _, phase in
            // The menu bar remains usable while welcome is open. Starting there
            // completes welcome without replacing that session's selected duration.
            if phase != .stopped && vm.storageError == nil { completeOnboarding() }
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        if let onComplete { onComplete() }
        else if isWindow { dismissWindow(id: "onboarding") }
        else { showOnboarding = false }
    }
}
