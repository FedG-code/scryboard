import UIKit
import UniformTypeIdentifiers
import ScryboardKit
import ScryboardUI

/// The keyboard. Opens in browsing mode — search-bar pill, results, a slim
/// toolbar with globe and delete — and switches to typing mode, where the
/// results give way to the QWERTY and a suggestion strip, when the bar is
/// tapped. Search, or a tapped suggestion, brings the results back.
final class KeyboardViewController: UIInputViewController {
    private enum Mode {
        case browsing
        case typing
    }

    private let searchBar = SearchBarView()
    private let resultsView = ResultsView()
    private let browseToolbar = BrowseToolbarView()
    private let suggestionStrip = SuggestionStripView()
    private let keyboardView = KeyboardView()
    private let fullAccessNotice = UILabel()
    private let toast = ToastView()

    private var browsingStack: UIStackView!
    private var typingStack: UIStackView!
    private var column: UIStackView!
    private var heightConstraint: NSLayoutConstraint?

    private var mode: Mode = .browsing
    private var query = ""
    private var keyboardState = KeyboardState()
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
        consumeOutcomes()
        showEmptyState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateHeight()
        refreshFullAccessState()
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

        typingStack = UIStackView(arrangedSubviews: [suggestionStrip, keyboardView])
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

        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)

        NSLayoutConstraint.activate([
            height,
            column.topAnchor.constraint(equalTo: view.topAnchor),
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            column.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            toast.centerXAnchor.constraint(equalTo: resultsView.centerXAnchor),
            toast.centerYAnchor.constraint(equalTo: resultsView.centerYAnchor),
            toast.widthAnchor.constraint(lessThanOrEqualTo: resultsView.widthAnchor, constant: -40),
        ])
    }

    private func wireActions() {
        searchBar.onTap = { [weak self] in self?.apply(mode: .typing, animated: true) }
        searchBar.onClear = { [weak self] in self?.clearQuery() }

        // iOS 26 draws its own globe under third-party keyboards; older
        // systems expect the keyboard to provide one.
        browseToolbar.globeButton.isHidden = !needsInputModeSwitchKey
        keyboardView.showsGlobeKey = needsInputModeSwitchKey
        browseToolbar.globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        browseToolbar.deleteButton.addTarget(self, action: #selector(deleteInHost), for: .touchUpInside)

        suggestionStrip.onSelect = { [weak self] name in self?.chooseSuggestion(name) }

        keyboardView.inputModeListHandler = self
        keyboardView.onAction = { [weak self] action in self?.perform(action) }
        keyboardView.onShiftDoubleTap = { [weak self] in
            guard let self else { return }
            keyboardState = keyboardState.lockingShift()
            keyboardView.render(keyboardState.layout)
        }

        resultsView.onSelect = { [weak self] card in self?.copy(card) }
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

    private func queryChanged() {
        searchBar.query = query
        let current = query
        Task { await pipeline.typed(current) }
    }

    private func commitSearch() {
        let current = query
        apply(mode: .browsing, animated: true)
        guard !current.isEmpty else { return }
        Task { await pipeline.search(current) }
    }

    private func chooseSuggestion(_ name: String) {
        query = name
        searchBar.query = name
        apply(mode: .browsing, animated: true)
        Task { await pipeline.searchExact(name: name) }
    }

    private func clearQuery() {
        query = ""
        searchBar.query = ""
        suggestionStrip.show([])
        Task { await pipeline.cancel() }
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
                self?.toast.show("Copied — tap and hold to paste")
            } catch {
                self?.toast.show("Couldn’t copy. Check your connection.")
            }
        }
    }

    @objc private func deleteInHost() {
        textDocumentProxy.deleteBackward()
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
            suggestionStrip.show([])
            showEmptyState()
        case .names(let names, _):
            suggestionStrip.show(names)
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
