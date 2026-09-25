import Observation

@MainActor
@Observable
final class OnboardingViewModel {
    let pages = OnboardingPage.pages
    var selectedPage = 0

    var isLastPage: Bool {
        selectedPage == pages.count - 1
    }

    func continueAction(onCompletion: () -> Void) {
        if isLastPage {
            onCompletion()
        } else {
            selectedPage += 1
        }
    }
}
