import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The "try it" field. A text view that takes images as well as text, since
/// pasting or dropping a card is the whole point: the stock SwiftUI text
/// field silently ignores both.
struct ScratchPad: UIViewRepresentable {
    @Binding var isEditing: Bool

    func makeUIView(context: Context) -> ScratchTextView {
        let view = ScratchTextView()
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: ScratchTextView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: ScratchPad
        init(_ parent: ScratchPad) { self.parent = parent }

        func textViewDidBeginEditing(_ textView: UITextView) { parent.isEditing = true }
        func textViewDidEndEditing(_ textView: UITextView) { parent.isEditing = false }
        func textViewDidChange(_ textView: UITextView) {
            (textView as? ScratchTextView)?.updatePlaceholder()
        }
    }
}

/// Accepts an image from the pasteboard (the Paste menu shows whenever one
/// is there) or from a drop, and shows it inline at card size.
final class ScratchTextView: UITextView, UITextDropDelegate {
    private let placeholder = UILabel()

    init() {
        super.init(frame: .zero, textContainer: nil)
        font = .preferredFont(forTextStyle: .body)
        backgroundColor = .clear
        isScrollEnabled = false
        textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textContainer.lineFragmentPadding = 0
        pasteConfiguration = UIPasteConfiguration(forAccepting: UIImage.self)
        textDropDelegate = self

        placeholder.text = "Tap here, switch to Scryboard with the globe key, then tap a card and paste it here, or drag one in."
        placeholder.font = font
        placeholder.textColor = .placeholderText
        placeholder.numberOfLines = 0
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            placeholder.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholder.widthAnchor.constraint(equalTo: widthAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func updatePlaceholder() {
        placeholder.isHidden = !text.isEmpty || attributedText.length > 0
    }

    // MARK: Paste

    override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
        itemProviders.contains { $0.canLoadObject(ofClass: UIImage.self) }
    }

    override func paste(itemProviders: [NSItemProvider]) {
        insertImages(from: itemProviders)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), UIPasteboard.general.hasImages {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        if UIPasteboard.general.hasImages {
            insertImages(from: UIPasteboard.general.itemProviders)
        } else {
            super.paste(sender)
        }
    }

    // MARK: Drop

    func textDroppableView(_ textDroppableView: UIView & UITextDroppable, proposalForDrop drop: UITextDropRequest) -> UITextDropProposal {
        guard drop.dropSession.canLoadObjects(ofClass: UIImage.self) else {
            return drop.suggestedProposal
        }
        return UITextDropProposal(operation: .copy)
    }

    func textDroppableView(_ textDroppableView: UIView & UITextDroppable, willPerformDrop drop: UITextDropRequest) {
        guard drop.dropSession.canLoadObjects(ofClass: UIImage.self) else { return }
        insertImages(from: drop.dropSession.items.map(\.itemProvider), at: drop.dropPosition)
    }

    // MARK: Insertion

    private func insertImages(from providers: [NSItemProvider], at position: UITextPosition? = nil) {
        for provider in providers where provider.canLoadObject(ofClass: UIImage.self) {
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let image = object as? UIImage else { return }
                DispatchQueue.main.async { self?.insert(image, at: position) }
            }
        }
    }

    private func insert(_ image: UIImage, at position: UITextPosition?) {
        let attachment = NSTextAttachment(image: image)
        let width = min(200, bounds.width)
        attachment.bounds = CGRect(x: 0, y: 0, width: width, height: width * image.size.height / max(image.size.width, 1))
        let text = NSMutableAttributedString(attributedString: attributedText)
        let location = position.map { offset(from: beginningOfDocument, to: $0) } ?? selectedRange.location
        let insertion = NSMutableAttributedString(attachment: attachment)
        insertion.append(NSAttributedString(string: "\n"))
        text.insert(insertion, at: min(location, text.length))
        attributedText = text
        font = .preferredFont(forTextStyle: .body)
        selectedRange = NSRange(location: min(location, text.length) + insertion.length, length: 0)
        updatePlaceholder()
        delegate?.textViewDidChange?(self)
        invalidateIntrinsicContentSize()
    }
}
