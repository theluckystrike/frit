import SwiftUI
import AppKit
import GlazeCore

@main
struct GlazeMainApp: App {
    init() {
        // Start in a book, not in the Open panel (I6 C2). macOS shows the Open panel at launch for document
        // apps unless this is false; with false, a launch without a file opens an untitled book. On the first
        // launch only, that untitled book makes way for the sample book (see BookWindow and FirstLaunch).
        UserDefaults.standard.register(defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false])
    }

    var body: some Scene {
        DocumentGroup(newDocument: GlazeDocument()) { file in
            BookWindow(document: Self.changesOnly(file.$document), isUntitled: file.fileURL == nil)
        }
        // 1320 x 780, capped to the screen's visible frame, so that the recipe table, the chemistry and the
        // Stull chart are all in view on a 1440 x 900 screen with the Dock showing, and the window fits a
        // 1024 x 768 screen (G11). The recipe table scrolls inside itself before the window grows (G10).
        .defaultSize(Self.defaultWindowSize)
        .commands {
            // View > Show/Hide Sidebar (Control-Command-S) and Show/Hide Chemistry (Option-Command-I).
            SidebarCommands()
            // View > Show/Hide Toolbar and Customize Toolbar… (I6 C14).
            ToolbarCommands()
            ChemistryCommands()
            // View > Recipes (Command-1), Tests (Command-2), Materials (Command-3) (W5 V2).
            PageCommands()
            // Recipe menu: add, rename, duplicate, delete, add material, blends, batch sheet.
            RecipeCommands()
            // Tests menu: Add Test, Find Test (Option-Command-F), Print Labels (F3).
            TestsCommands()
            // File > Print… (Command-P) prints the batch sheet of the selected recipe (I6 C7).
            PrintCommands()
            CommandGroup(replacing: .help) {
                HelpMenuItems()
            }
        }

        // Help > Frit Help (Command-?). The help text is in the app, so it works without a network connection.
        Window(Text("\(AppInfo.name) Help"), id: HelpWindow.id) {
            HelpWindow()
        }
        .defaultSize(width: 560, height: 640)
        .windowResizability(.contentMinSize)
    }

    /// The default window size for the main screen: the preferred size, capped to the screen's visible frame.
    @MainActor
    static var defaultWindowSize: CGSize {
        let size = WindowLayout.defaultSize(visible: visibleScreen(NSScreen.main))
        return CGSize(width: size.width, height: size.height)
    }

    /// The visible frame of `screen` (the part that windows can use), or nil without a screen.
    @MainActor
    static func visibleScreen(_ screen: NSScreen?) -> LayoutSize? {
        var visible = screen.map { LayoutSize(width: Double($0.visibleFrame.width), height: Double($0.visibleFrame.height)) }
        #if DEBUG
        // QA only (debug builds): `-FritQAVisibleSize 1024x700` stands in for a smaller screen's visible frame.
        // This code is not compiled into the release build (G11: no hidden launch arguments in the product).
        if let simulated = WindowLayout.parseSize(UserDefaults.standard.string(forKey: "FritQAVisibleSize")) {
            visible = simulated
        }
        #endif
        return visible
    }

    /// A document binding that ignores writes of an unchanged book. SwiftUI text fields write back their
    /// unchanged text when they take focus; a write through the document binding marks the book "Edited"
    /// and autosaves it, so opening a book used to change it (G5 defect 1).
    @MainActor
    static func changesOnly(_ binding: Binding<GlazeDocument>) -> Binding<GlazeDocument> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue, transaction in
                guard newValue.book != binding.wrappedValue.book else { return }
                binding.transaction(transaction).wrappedValue = newValue
            }
        )
    }
}

/// Web pages that the Help menu opens in the default browser. The app itself makes no network request:
/// the system hands the URL to the browser, so no network entitlement is needed.
enum HelpLinks {
    static let support = URL(string: "https://frit-app.pages.dev/support/")!
    static let privacy = URL(string: "https://frit-app.pages.dev/privacy/")!
}

enum AppInfo {
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Frit"
    }
}

/// Items for the Help menu. A view, so that it can read the document actions from the environment.
struct HelpMenuItems: View {
    @Environment(\.newDocument) private var newDocument
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("\(AppInfo.name) Help") { openWindow(id: HelpWindow.id) }
            .keyboardShortcut("?", modifiers: .command)
            .accessibilityHint("Opens the help window")
        Divider()
        Button("\(AppInfo.name) Support") { NSWorkspace.shared.open(HelpLinks.support) }
            .accessibilityHint("Opens the support page in your web browser")
        Button("Privacy Policy") { NSWorkspace.shared.open(HelpLinks.privacy) }
            .accessibilityHint("Opens the privacy policy in your web browser")
        Divider()
        Button("Open Sample Book") {
            newDocument(GlazeDocument.sample())
        }
        .accessibilityHint("Opens a new untitled book with six sample cone 6 recipes")
    }
}
