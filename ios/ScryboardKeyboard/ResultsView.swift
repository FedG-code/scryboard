import UIKit
import UniformTypeIdentifiers
import ScryboardKit
import ScryboardUI

/// The card grid. Cells show Scryfall's `normal` scan at every card size
/// (decided 2026-09-22), decoded at cell size through `ImageStore` so the
/// extension stays far under its memory ceiling.
final class ResultsView: UIView {
    enum Status {
        case hint(String)
        case loading
        case message(String)
        case cards
    }

    var onSelect: ((Card) -> Void)?
    /// A held card. Tap copies; hold shows every printing.
    var onLongPress: ((Card) -> Void)?
    /// Set by the owner while the grid shows every printing of one card, so
    /// holding a card does nothing rather than expanding it again.
    var showsPrintings = false
    /// What a drag hands over: the same thing a tap would copy. Set by the
    /// owner from the preferences.
    var copyFormat: CopyFormat = .image
    /// A drag ended over the host app. `accepted` is false when the app
    /// refused the drop; a drag let go over the keyboard itself is not
    /// reported, since nothing was refused.
    var onDragEnded: ((Card, _ accepted: Bool) -> Void)?
    /// Called as cells come on screen, so the owner can page in more results.
    var onCardAppeared: ((Int) -> Void)?
    /// The grid stopped moving. The owner notes where it is.
    var onScrollSettled: (() -> Void)?
    /// The user pinched the grid to a new size. The owner persists it.
    var onPinchToSize: ((CardSize) -> Void)?

    /// Columns and scan follow this. Setting it re-lays the grid out in place.
    var cardSize: CardSize = .medium {
        didSet {
            guard cardSize != oldValue else { return }
            collection.collectionViewLayout.invalidateLayout()
            UIView.transition(with: collection, duration: 0.2, options: .transitionCrossDissolve) {
                self.collection.reloadData()
            }
        }
    }

    private(set) var cards: [Card] = []
    /// The card at the top of the grid, or `nil` while it is empty. Stored
    /// as an index rather than an offset so it survives a change of card size.
    var firstVisibleIndex: Int? {
        collection.indexPathsForVisibleItems.map(\.item).min()
    }

    private let collection: UICollectionView
    private lazy var dragInteraction = UIDragInteraction(delegate: self)
    /// A card is moving. The hold recognizer stands down meanwhile.
    private var dragging = false
    /// Where to scroll once the grid has a size. Set by `show(_:scrollTo:)`
    /// before the first layout, when scrolling would have nowhere to go.
    private var pendingScroll: Int?
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    /// Card scans are 5:7. As many columns as the chosen card size allows:
    /// on a phone 4, 3 or 2. Wider screens get more.
    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] _, environment in
            let width = environment.container.effectiveContentSize.width
            let target = self?.cardSize.targetCellWidth ?? CardSize.medium.targetCellWidth
            let columns = max(2, Int(width / target))
            let spacing: CGFloat = 8
            let item = NSCollectionLayoutItem(layoutSize: .init(
                widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
                heightDimension: .fractionalHeight(1)
            ))
            let cellWidth = (width - spacing * CGFloat(columns + 1)) / CGFloat(columns)
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(cellWidth * 7 / 5)),
                repeatingSubitem: item, count: columns
            )
            group.interItemSpacing = .fixed(spacing)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = spacing
            section.contentInsets = NSDirectionalEdgeInsets(top: spacing, leading: spacing, bottom: spacing, trailing: spacing)
            return section
        }
    }

    override init(frame: CGRect) {
        collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        super.init(frame: frame)

        collection.collectionViewLayout = makeLayout()
        collection.backgroundColor = .clear
        collection.dataSource = self
        collection.delegate = self
        collection.register(CardCell.self, forCellWithReuseIdentifier: CardCell.reuseIdentifier)
        // Cards drag out of the grid into the host app. Our own interaction
        // rather than the collection view's drag delegate, because only this
        // one hears how the drop ended. Enabled explicitly: the default is
        // iPad only.
        dragInteraction.isEnabled = true
        collection.addInteraction(dragInteraction)
        collection.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collection)

        // Longer than the system's drag lift (about half a second), so a
        // hold that was going to become a drag has already done so.
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.7
        collection.addGestureRecognizer(hold)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        collection.addGestureRecognizer(pinch)

        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)

        NSLayoutConstraint.activate([
            collection.topAnchor.constraint(equalTo: topAnchor),
            collection.bottomAnchor.constraint(equalTo: bottomAnchor),
            collection.leadingAnchor.constraint(equalTo: leadingAnchor),
            collection.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Fires once the hold has outlasted the drag lift with no drag begun.
    /// The system lifts the card at about half a second; a hold that gets
    /// this far was not going to drag, so the lift is cancelled and the card
    /// settles back as the printings come in. Does nothing while the grid
    /// already shows printings: there is nothing further to expand.
    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !dragging, !showsPrintings,
              let indexPath = collection.indexPathForItem(at: gesture.location(in: collection))
        else { return }
        cancelLift()
        onLongPress?(cards[indexPath.item])
    }

    /// Disabling the interaction tears its recognizers down, which ends a
    /// lift in progress. It comes back on the next run loop turn, too late to
    /// see the touch that is still down.
    private func cancelLift() {
        dragInteraction.isEnabled = false
        DispatchQueue.main.async { [dragInteraction] in dragInteraction.isEnabled = true }
    }

    /// One size step per pinch, in the direction of the gesture. Anything
    /// under a quarter either way is treated as a wobble.
    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let next: CardSize?
        if gesture.scale > 1.25 {
            next = cardSize.larger
        } else if gesture.scale < 0.8 {
            next = cardSize.smaller
        } else {
            next = nil
        }
        guard let next else { return }
        cardSize = next
        onPinchToSize?(next)
    }

    func show(_ status: Status) {
        switch status {
        case .hint(let text), .message(let text):
            cards = []
            collection.reloadData()
            collection.isHidden = true
            statusLabel.text = text
            statusLabel.isHidden = false
            spinner.stopAnimating()
        case .loading:
            collection.isHidden = true
            statusLabel.isHidden = true
            spinner.startAnimating()
        case .cards:
            collection.isHidden = false
            statusLabel.isHidden = true
            spinner.stopAnimating()
        }
    }

    /// Replace the grid. Lands on `scrollTo`, a card index, or at the top.
    func show(_ cards: [Card], scrollTo index: Int = 0) {
        self.cards = cards
        collection.reloadData()
        collection.setContentOffset(.zero, animated: false)
        pendingScroll = index > 0 && index < cards.count ? index : nil
        show(.cards)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let index = pendingScroll, collection.bounds.height > 0 else { return }
        pendingScroll = nil
        collection.layoutIfNeeded()
        collection.scrollToItem(at: IndexPath(item: index, section: 0), at: .top, animated: false)
    }

    /// Append a page without disturbing the scroll position.
    func append(_ more: [Card]) {
        guard !more.isEmpty else { return }
        let start = cards.count
        cards.append(contentsOf: more)
        collection.insertItems(at: (start..<cards.count).map { IndexPath(item: $0, section: 0) })
    }
}

extension ResultsView: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        cards.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CardCell.reuseIdentifier, for: indexPath) as! CardCell
        cell.show(cards[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        onCardAppeared?(indexPath.item)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(cards[indexPath.item])
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        onScrollSettled?()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { onScrollSettled?() }
    }
}

extension ResultsView: UIDragInteractionDelegate {
    /// One item, shaped by the copy format. For images the card's page link
    /// rides along as a second representation, so a field that takes no
    /// images (Reddit, a chat's text box) still gets something; a field that
    /// takes both may prefer the link, which is the receiver's call. The JPEG
    /// is fetched only if something accepts the drop.
    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        guard let indexPath = collection.indexPathForItem(at: session.location(in: collection)) else { return [] }
        let card = cards[indexPath.item]
        let provider = NSItemProvider()
        provider.suggestedName = card.name
        switch copyFormat {
        case .image:
            guard let url = card.imageURL(.normal) else { return [] }
            provider.registerDataRepresentation(forTypeIdentifier: UTType.jpeg.identifier, visibility: .all) { completion in
                let progress = Progress(totalUnitCount: 1)
                Task {
                    do {
                        let data = try await ImageStore.shared.imageData(for: url)
                        progress.completedUnitCount = 1
                        completion(data, nil)
                    } catch {
                        completion(nil, error)
                    }
                }
                return progress
            }
            if let page = card.pageURL {
                provider.registerObject(page as NSURL, visibility: .all)
            }
        case .link:
            guard let page = card.pageURL else { return [] }
            provider.registerObject(page as NSURL, visibility: .all)
        case .text:
            let text = showsPrintings ? card.decklistLine : card.name
            provider.registerObject(text as NSString, visibility: .all)
        }
        let item = UIDragItem(itemProvider: provider)
        item.localObject = card
        return [item]
    }

    /// Lift the cell alone, not a snapshot of the whole grid.
    func dragInteraction(_ interaction: UIDragInteraction, previewForLifting item: UIDragItem, session: UIDragSession) -> UITargetedDragPreview? {
        guard let indexPath = collection.indexPathForItem(at: session.location(in: collection)),
              let cell = collection.cellForItem(at: indexPath)
        else { return nil }
        let parameters = UIDragPreviewParameters()
        parameters.visiblePath = UIBezierPath(roundedRect: cell.bounds, cornerRadius: 6)
        return UITargetedDragPreview(view: cell, parameters: parameters)
    }

    func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: UIDragSession) {
        dragging = true
    }

    /// The only word back from a drop: whether anything took it. A drag let
    /// go over the grid itself was abandoned, not refused, and is not reported.
    func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession, didEndWith operation: UIDropOperation) {
        dragging = false
        guard let card = session.items.first?.localObject as? Card else { return }
        switch operation {
        case .copy, .move:
            onDragEnded?(card, true)
        case .cancel, .forbidden:
            if !collection.bounds.contains(session.location(in: collection)) {
                onDragEnded?(card, false)
            }
        @unknown default:
            break
        }
    }
}

/// One card scan. Loads its thumbnail asynchronously and drops the load on
/// reuse so a fast scroll never decodes images nobody will see.
final class CardCell: UICollectionViewCell {
    static let reuseIdentifier = "card"

    private let imageView = UIImageView()
    private var load: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .quaternarySystemFill
        contentView.layer.cornerRadius = 6
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func prepareForReuse() {
        super.prepareForReuse()
        load?.cancel()
        load = nil
        imageView.image = nil
    }

    func show(_ card: Card) {
        accessibilityLabel = card.name
        isAccessibilityElement = true
        guard let url = card.imageURL(.normal) else { return }
        // Never decode past the scan's own height, 680 px. The cell is usually
        // smaller still, and that is the cap.
        let maxPixels = min(680, Int(bounds.height * traitCollection.displayScale))
        load = Task { [weak self] in
            guard let image = try? await ImageStore.shared.thumbnail(for: url, maxPixelSize: max(maxPixels, 100)) else { return }
            guard !Task.isCancelled, let self else { return }
            UIView.transition(with: self.imageView, duration: 0.15, options: .transitionCrossDissolve) {
                self.imageView.image = UIImage(cgImage: image)
            }
        }
    }
}
