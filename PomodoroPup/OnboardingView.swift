import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var vm: DogViewModel
    @Binding var showOnboarding: Bool
    @Environment(\.dismissWindow) var dismissWindow
    var isWindow: Bool = false  // 是否作为独立窗口显示
    @State private var currentPage = 0

    var body: some View {
        VStack(spacing: 20) {
            if currentPage == 0 {
                // 欢迎页
                Image("dog_work")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)

                Text(NSLocalizedString("onboarding.welcome.title", comment: ""))
                    .font(.title2)
                    .bold()

                Text(NSLocalizedString("onboarding.welcome.subtitle", comment: ""))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                Button(NSLocalizedString("onboarding.next", comment: "")) {
                    currentPage = 1
                }
                .buttonStyle(PrimaryButtonStyle())

            } else if currentPage == 1 {
                // 设置目标页
                Text(NSLocalizedString("onboarding.goal.title", comment: ""))
                    .font(.title2)
                    .bold()

                Text(NSLocalizedString("onboarding.goal.subtitle", comment: ""))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                HStack(spacing: 16) {
                    ForEach([2, 4, 6, 8], id: \.self) { count in
                        Button("\(count)") {
                            vm.dailyGoal = count
                        }
                        .frame(width: 50, height: 50)
                        .background(vm.dailyGoal == count ? Color.black : Color.gray.opacity(0.2))
                        .foregroundColor(vm.dailyGoal == count ? .white : .black)
                        .cornerRadius(8)
                    }
                }

                Spacer()

                Button(NSLocalizedString("onboarding.next", comment: "")) {
                    currentPage = 2
                }
                .buttonStyle(PrimaryButtonStyle())

            } else {
                // 通知权限页
                Image(systemName: "bell.badge")
                    .font(.system(size: 60))
                    .foregroundColor(.black)

                Text(NSLocalizedString("onboarding.notification.title", comment: ""))
                    .font(.title2)
                    .bold()

                Text(NSLocalizedString("onboarding.notification.subtitle", comment: ""))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                VStack(spacing: 12) {
                    Button(NSLocalizedString("onboarding.enable", comment: "")) {
                        vm.requestNotificationPermission()
                        completeOnboarding()
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button(NSLocalizedString("onboarding.skip", comment: "")) {
                        completeOnboarding()
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: 320, height: 400)
        .padding()
        .background(Color.white)
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        if isWindow {
            dismissWindow(id: "onboarding")
        } else {
            showOnboarding = false
        }
    }
}
