import UIKit

/// Receives only providers selected through Apple's explicit paste control.
/// This avoids background polling of UIPasteboard and works without Full Access.
final class KeyboardPasteTarget: NSObject, UIPasteConfigurationSupporting {
    var didRequestPaste: ((NSItemProvider) -> Void)?

    var pasteConfiguration: UIPasteConfiguration? {
        get { UIPasteConfiguration(forAccepting: NSString.self) }
        set { /* This target only accepts plain text. */ }
    }

    func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
        itemProviders.contains { $0.canLoadObject(ofClass: NSString.self) }
    }

    func paste(itemProviders: [NSItemProvider]) {
        guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return }
        didRequestPaste?(provider)
    }
}
