import UIKit
import UniformTypeIdentifiers
import ScryboardKit
import ScryboardUI

/// The keyboard. Opens in browsing mode — search-bar pill, results, a slim
/// toolbar with a globe where the system draws none — and switches to typing
/// mode, where the results give way to the QWERTY, when the bar is tapped.
/// The return key brings the results back.
final class KeyboardViewController: UIInputViewController {
    private enum Mode {
        case browsing
        case typing
    }

    private let searchBar = SearchBarView()
    private let resultsView = ResultsView()
    private let browseToolbar = BrowseToolbarView()
    /// Floats over the grid while printings are shown. The one way back.
    private let backButton = UIButton(configuration: .filled())
    private let keyboardView = KeyboardView()
    private let fullAccessNotice = UILabel()
    private let toast = ToastView()

    private var browsingStack: UIStackView!
    private var typingStack: UIStackView!
    private var column: UIStackView!
    private var heightConstraint: NSLayoutConstraint?

    private var mode: Mode = .browsing
    /// What the user typed. Stays in the pill while printings are shown.
    private var query = ""
    /// The held card whose printings fill the grid, if any.
    private var printings: String?
    private var keyboardState = KeyboardState()
    /// Re-read on every appearance, so a change in the app shows next time.
    private var preferences = Preferences()
    private let client = ScryfallClient()
    private lazy var pipeline = SearchPipeline(client: client)
    private var outcomeTask: Task<Void, Never>?
    /// Pages the current search as the grid scrolls. Replaced per search.
    private var pager: ResultsPager?
    private var copyTask: Task<Void, Never>?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Size from our own content rather than a constraint on the root view,
        // which iOS 26 stops honouring after the first layout pass; the
        // keyboard then collapsed to the search bar's height.
        inputView?.allowsSelfSizing = true
        buildHierarchy()
        wireActions()
        keyboardView.render(keyboardState.layout)
        apply(mode: .browsing, animated: false)
        applyPreferences()
        consumeOutcomes()
        restoreLastSearch()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateHeight()
        refreshFullAccessState()
        applyPreferences()
    }

    private func applyPreferences() {
        preferences = PreferencesStore.shared.load()
        resultsView.cardSize = preferences.cardSize
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateHeight()
    }

    deinit {
        outcomeTask?.cancel()
    }

    // MARK: - Hierarchy

    private func buildHierarchy() {
        browsingStack = UIStackView(arrangedSubviews: [resultsView, browseToolbar])
        browsingStack.axis = .vertical

        typingStack = UIStackView(arrangedSubviews: [keyboardView])
        typingStack.axis = .vertical

        fullAccessNotice.text = "Scryboard needs Full Access to reach Scryfall.\nSettings › General › Keyboard › Keyboards › Scryboard › Allow Full Access"
        fullAccessNotice.font = .preferredFont(forTextStyle: .subheadline)
        fullAccessNotice.textColor = .secondaryLabel
        fullAccessNotice.textAlignment = .center
        fullAccessNotice.numberOfLines = 0
        fullAccessNotice.isHidden = true

        column = UIStackView(arrangedSubviews: [searchBar, fullAccessNotice, browsingStack, typingStack])
        column.axis = .vertical
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)

        let height = column.heightAnchor.constraint(equalToConstant: preferredHeight)
        height.priority = UILayoutPriority(999)
        heightConstraint = height

        var back = backButton.configuration ?? .filled()
        back.cornerStyle = .capsule
        back.image = UIImage(systemName: "chevron.left")
        back.imagePadding = 4
        back.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        back.attributedTitle = AttributedString("Back", attributes: AttributeContainer([
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
        ]))
        back.baseBackgroundColor = .systemFill
        back.baseForegroundColor = .label
        back.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 14)
        backButton.configuration = back
        backButton.layer.shadowColor = UIColor.black.cgColor
        backButton.layer.shadowOpacity = 0.35
        backButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        backButton.layer.shadowRadius = 5
        backButton.accessibilityLabel = "Back to search results"
        backButton.isHidden = true
        backButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backButton)

        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)

        NSLayoutConstraint.activate([
            height,
            column.topAnchor.constraint(equalTo: view.topAnchor),
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            column.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            // Bottom right, where the thumb already is after a long press.
            backButton.trailingAnchor.constraint(equalTo: resultsView.trailingAnchor, constant: -12),
            backButton.bottomAnchor.constraint(equalTo: resultsView.bottomAnchor, constant: -12),
            toast.centerXAnchor.constraint(equalTo: resultsView.centerXAnchor),
            toast.centerYAnchor.constraint(equalTo: resultsView.centerYAnchor),
            toast.widthAnchor.constraint(lessThanOrEqualTo: resultsView.widthAnchor, constant: -40),
        ])
    }

    private func wireActions() {
        searchBar.onTap = { [weak self] in self?.apply(mode: .typing, animated: true) }
        searchBar.onClear = { [weak self] in self?.clearQuery() }
        backButton.addAction(UIAction { [weak self] _ in self?.leavePrintings() }, for: .touchUpInside)

        // iOS 26 draws its own globe under third-party keyboards; older
        // systems expect the keyboard to provide one.
        browseToolbar.isHidden = !needsInputModeSwitchKey
        keyboardView.showsGlobeKey = needsInputModeSwitchKey
        browseToolbar.globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        keyboardView.inputModeListHandler = self
        keyboardView.onAction = { [weak self] action in self?.perform(action) }
        keyboardView.onShiftDoubleTap = { [weak self] in
            guard let self else { return }
            keyboardState = keyboardState.lockingShift()
            keyboardView.render(keyboardState.layout)
        }

        resultsView.onSelect = { [weak self] card in self?.copy(card) }
        resultsView.onLongPress = { [weak self] card in self?.showPrintings(of: card) }
        resultsView.onPinchToSize = { [weak self] size in
            guard let self else { return }
            preferences.cardSize = size
            PreferencesStore.shared.save(preferences)
            toast.show("\(size.title) cards")
        }
        resultsView.onCardAppeared = { [weak self] index in
            guard let self, let pager else { return }
            Task { [weak self] in
                await pager.cardAppeared(at: index)
                guard let self, self.pager === pager else { return }
                let loaded = await pager.cards
                if loaded.count > self.resultsView.cards.count {
                    self.resultsView.append(Array(loaded[self.resultsView.cards.count...]))
                }
            }
        }
    }

    // MARK: - Height

    /// One height for both modes, so switching never shifts the host app's
    /// content underneath the user's thumb.
    private var preferredHeight: CGFloat {
        if traitCollection.userInterfaceIdiom == .pad {
            400
        } else if traitCollection.verticalSizeClass == .compact {
            220
        } else {
            320
        }
    }

    private func updateHeight() {
        heightConstraint?.constant = preferredHeight
    }

    // MARK: - Modes

    private func apply(mode: Mode, animated: Bool) {
        self.mode = mode
        let changes = {
            self.browsingStack.isHidden = mode == .typing
            self.typingStack.isHidden = mode == .browsing
            self.searchBar.isEditing = mode == .typing
            self.backButton.isHidden = mode == .typing || self.printings == nil
        }
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState], animations: changes)
        } else {
            changes()
        }
        if mode == .typing {
            keyboardState = KeyboardState()
            keyboardView.render(keyboardState.layout)
        }
    }

    private func refreshFullAccessState() {
        let allowed = hasFullAccess
        fullAccessNotice.isHidden = allowed
        searchBar.isUserInteractionEnabled = allowed
        resultsView.isHidden = !allowed
        backButton.isHidden = !allowed || mode == .typing || printings == nil
        if !allowed, mode == .typing {
            apply(mode: .browsing, animated: false)
        }
    }

    // MARK: - Key presses

    private func perform(_ action: KeyAction) {
        let transition = keyboardState.applying(action)
        keyboardState = transition.state
        keyboardView.render(keyboardState.layout)

        switch transition.effect {
        case .none:
            break
        case .insert(let text):
            query += text
            queryChanged()
        case .deleteBackward:
            guard !query.isEmpty else { return }
            query.removeLast()
            queryChanged()
        case .submit:
            commitSearch()
        case .advanceToNextInputMode:
            advanceToNextInputMode()
        }
    }

    /// Keystrokes only edit the bar. Nothing is sent until the return key:
    /// the name-suggestion strip that used to fire `/cards/autocomplete` here
    /// was dropped for the syntax row, so there is no request to debounce.
    private func queryChanged() {
        searchBar.query = query
    }

    private func commitSearch() {
        let current = query
        printings = nil
        apply(mode: .browsing, animated: true)
        SavedSearch.remember(query: current, printings: nil)
        guard !current.isEmpty else {
            showEmptyState()
            return
        }
        runSearch(current)
    }

    /// A typed query, sorted the way the user chose in the app. A query that
    /// says `order:` itself keeps its own; the client drops the parameter.
    private func runSearch(_ query: String) {
        let order = preferences.order
        let direction = preferences.direction
        Task { await pipeline.search(query, order: order, direction: direction) }
    }

    private func clearQuery() {
        query = ""
        searchBar.query = ""
        printings = nil
        backButton.isHidden = true
        SavedSearch.clear()
        Task { await pipeline.cancel() }
    }

    /// Every printing of a card, newest first. Commander players care which
    /// art they send. Reached by holding a card. The pill keeps the query the
    /// user typed; the floating Back button returns to it.
    private func showPrintings(of card: Card) {
        printings = card.name
        backButton.isHidden = false
        toast.show("All printings of \(card.name)")
        SavedSearch.remember(query: query, printings: card.name)
        Task { await pipeline.searchExact(name: card.name) }
    }

    /// Back from the printings view to whatever filled the grid before it.
    private func leavePrintings() {
        printings = nil
        backButton.isHidden = true
        SavedSearch.remember(query: query, printings: nil)
        let current = query
        if current.isEmpty {
            showEmptyState()
        } else {
            runSearch(current)
        }
    }

    /// The host rebuilds the keyboard on every dismissal, and pasting a copied
    /// card dismisses it, so the last search is re-run rather than lost.
    private func restoreLastSearch() {
        guard let saved = SavedSearch.load() else {
            showEmptyState()
            return
        }
        query = saved.query
        searchBar.query = saved.query
        printings = saved.printings
        backButton.isHidden = saved.printings == nil
        if let name = saved.printings {
            Task { await pipeline.searchExact(name: name) }
        } else {
            runSearch(saved.query)
        }
    }

    // MARK: - Empty state

    /// Recents once the user has copied something; before that, the most
    /// popular cards, so the keyboard is never a blank box.
    private func showEmptyState() {
        pager = nil
        let recents = RecentCards.load()
        if !recents.isEmpty {
            resultsView.show(recents)
        } else {
            Task { await pipeline.search("game:paper", order: .edhrec, direction: .ascending) }
        }
    }

    // MARK: - Copying

    /// The product: full-size scan to the pasteboard, toast, let the bytes go.
    private func copy(_ card: Card) {
        guard let url = card.imageURL(.normal) else { return }
        copyTask?.cancel()
        toast.show("Copying…")
        copyTask = Task { [weak self] in
            do {
                let data = try await ImageStore.shared.imageData(for: url)
                guard !Task.isCancelled else { return }
                UIPasteboard.general.setData(data, forPasteboardType: UTType.jpeg.identifier)
                RecentCards.remember(card)
                self?.toast.show("Copied")
            } catch {
                self?.toast.show("Couldn’t copy. Check your connection.")
            }
        }
    }

    // MARK: - Outcomes

    private func consumeOutcomes() {
        outcomeTask = Task { [weak self, pipeline] in
            for await outcome in pipeline.outcomes {
                guard let self else { return }
                self.handle(outcome)
            }
        }
    }

    private func handle(_ outcome: SearchOutcome) {
        switch outcome {
        case .idle:
            showEmptyState()
        case .names:
            // No suggestion strip any more; the pipeline still offers names
            // for the Android port and the container app.
            break
        case .loading:
            resultsView.show(.loading)
        case .cards(let page, _):
            pager = ResultsPager(client: client, firstPage: page)
            resultsView.show(page.data)
        case .empty(let query):
            resultsView.show(.message("No cards match “\(query)”."))
        case .failure(let error, _):
            resultsView.show(.message(error.localizedDescription))
        }
    }
}
