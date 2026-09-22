import UIKit
import ScryboardKit
import ScryboardUI

/// The card grid. Cells show the scan the card size calls for (`small` for
/// small cells, `normal` otherwise), decoded at cell size through
/// `ImageStore` so the extension stays far under its memory ceiling.
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
    /// Called as cells come on screen, so the owner can page in more results.
    var onCardAppeared: ((Int) -> Void)?
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
    private let collection: UICollectionView
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
        collection.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collection)

        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.4
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

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let indexPath = collection.indexPathForItem(at: gesture.location(in: collection))
        else { return }
        onLongPress?(cards[indexPath.item])
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

    func show(_ cards: [Card]) {
        self.cards = cards
        collection.reloadData()
        collection.setContentOffset(.zero, animated: false)
        show(.cards)
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
        cell.show(cards[indexPath.item], size: cardSize)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        onCardAppeared?(indexPath.item)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(cards[indexPath.item])
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

    func show(_ card: Card, size: CardSize) {
        accessibilityLabel = card.name
        isAccessibilityElement = true
        guard let url = card.imageURL(size.scan) else { return }
        // Never decode past the scan's own height: 204 px for small, 680 for
        // normal. The cell is usually smaller still, and that is the cap.
        let scanHeight = size.scan == .normal ? 680 : 204
        let maxPixels = min(scanHeight, Int(bounds.height * traitCollection.displayScale))
        load = Task { [weak self] in
            guard let image = try? await ImageStore.shared.thumbnail(for: url, maxPixelSize: max(maxPixels, 100)) else { return }
            guard !Task.isCancelled, let self else { return }
            UIView.transition(with: self.imageView, duration: 0.15, options: .transitionCrossDissolve) {
                self.imageView.image = UIImage(cgImage: image)
            }
        }
    }
}
