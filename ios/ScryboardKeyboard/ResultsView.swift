import UIKit
import ScryboardKit
import ScryboardUI

/// The card grid. Cells show Scryfall's `small` scan, decoded at cell size
/// through `ImageStore` so the extension stays far under its memory ceiling.
final class ResultsView: UIView {
    enum Status {
        case hint(String)
        case loading
        case message(String)
        case cards
    }

    var onSelect: ((Card) -> Void)?
    /// Called as cells come on screen, so the owner can page in more results.
    var onCardAppeared: ((Int) -> Void)?

    private(set) var cards: [Card] = []
    private let collection: UICollectionView
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    /// Card scans are 5:7. Three columns on a phone, more on wider screens.
    private static func layout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, environment in
            let width = environment.container.effectiveContentSize.width
            let columns = max(3, Int(width / 118))
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
        collection = UICollectionView(frame: .zero, collectionViewLayout: ResultsView.layout())
        super.init(frame: frame)

        collection.backgroundColor = .clear
        collection.dataSource = self
        collection.delegate = self
        collection.register(CardCell.self, forCellWithReuseIdentifier: CardCell.reuseIdentifier)
        collection.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collection)

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
        cell.show(cards[indexPath.item])
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

    func show(_ card: Card) {
        accessibilityLabel = card.name
        isAccessibilityElement = true
        guard let url = card.imageURL(.small) else { return }
        // Scryfall's small scan is 204 px tall; never ask for more than that.
        let maxPixels = min(204, Int(bounds.height * traitCollection.displayScale))
        load = Task { [weak self] in
            guard let image = try? await ImageStore.shared.thumbnail(for: url, maxPixelSize: max(maxPixels, 100)) else { return }
            guard !Task.isCancelled, let self else { return }
            UIView.transition(with: self.imageView, duration: 0.15, options: .transitionCrossDissolve) {
                self.imageView.image = UIImage(cgImage: image)
            }
        }
    }
}
