import Foundation

/// The first-launch rule (I6 C2). The first time the app starts, it shows the sample book, so that a new user
/// sees recipes, chemistry and the Stull chart at once. This is visible and documented: the sample window
/// says why it opened, and the Help window describes it. It happens once. After that, a launch opens an
/// untitled book, File > New makes another, and Help > Open Sample Book opens the sample again.
public enum FirstLaunch {
    /// The UserDefaults key that records that the first launch is over.
    public static let defaultsKey = "firstLaunchSampleShown"

    /// Whether a new book window replaces itself with the sample book.
    /// Only on the first launch, and only for an untitled, empty book (not for a file the user opened).
    public static func shouldOpenSample(firstLaunchDone: Bool, isUntitled: Bool, book: GlazeBook) -> Bool {
        !firstLaunchDone && isUntitled && book.recipes.isEmpty && book.tests.isEmpty && book.customMaterials.isEmpty
    }
}
