import UIKit
import UniformTypeIdentifiers
import ScryboardKit
import ScryboardUI

/// The keyboard. Opens on the query builder under the search-bar pill;
/// browsing mode shows results in a grid with a slim toolbar holding a globe
/// where the system draws none; typing mode gives the room to the QWERTY when
/// the bar is tapped. The return key or the builder's Search shows results;
/// the QWERTY's builder key comes back here.
final class KeyboardViewController: UIInputViewController {
    private enum Mode {
        /// The query builder. What an empty search bar shows.
        case building
        case browsing
        case typing
    }

    private let searchBar = SearchBarView()
    private let builderView = BuilderView()
    private let resultsView = ResultsView()
    private let browseToolbar = BrowseToolbarView()
    /// Floats over the grid while printings are shown. The one way back.
    private let backButton = BackCapsuleButton()
    private let keyboardView = KeyboardView()
    private let fullAccessNotice = UILabel()
    private let toast = ToastView()

    private var browsingStack: UIStackView!
    private var typingStack: UIStackView!
    private var buildingStack: UIStackView!
    private var column: UIStackView!
    private var heightConstraint: NSLayoutConstraint?

    private var mode: Mode = .building
    /// What the user typed, and where the caret sits in it. Stays in the
    /// pill while printings are shown.
    private var query = QueryBuffer()
    /// The held card whose printings fill the grid, if any.
    private var printings: String? {
        didSet { resultsView.showsPrintings = printings != nil }
    }
    private var keyboardState = KeyboardState()
    /// Re-read on every appearance, so a change in the app shows next time.
    private var preferences = Preferences()
    private let client = ScryfallClient()
    private lazy var pipeline = SearchPipeline(client: client)
    private var outcomeTask: Task<Void, Never>?
    /// Pages the current search as the grid scrolls. Replaced per search.
    private var pager: ResultsPager?
    /// The grid as it was before printings replaced it, so Back restores it
    /// in place: no request, same scroll position. One level.
    private var gridBeforePrintings: (pager: ResultsPager?, cards: [Card], firstVisible: Int)?
    /// Orders results writes; see `SavedResults.store`.
    private var resultsSequence = 0
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
        apply(mode: .building, animated: false)
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        rememberPosition()
    }

    private func applyPreferences() {
        preferences = PreferencesStore.shared.load()
        resultsView.cardSize = preferences.cardSize
        resultsView.copyFormat = preferences.copyFormat
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

        buildingStack = UIStackView(arrangedSubviews: [builderView])
        buildingStack.axis = .vertical

        fullAccessNotice.text = "Scryboard needs Full Access to reach Scryfall.\nSettings › General › Keyboard › Keyboards › Scryboard › Allow Full Access"
        fullAccessNotice.font = .preferredFont(forTextStyle: .subheadline)
        fullAccessNotice.textColor = .secondaryLabel
        fullAccessNotice.textAlignment = .center
        fullAccessNotice.numberOfLines = 0
        fullAccessNotice.isHidden = true

        column = UIStackView(arrangedSubviews: [searchBar, fullAccessNotice, buildingStack, browsingStack, typingStack])
        column.axis = .vertical
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)

        let height = column.heightAnchor.constraint(equalToConstant: preferredHeight)
        height.priority = UILayoutPriority(999)
        heightConstraint = height

        backButton.accessibilityLabel = "Back to search results"
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
        searchBar.onMoveCaret = { [weak self] offset in
            self?.query.moveCaret(to: offset)
            self?.queryChanged()
        }
        backButton.addAction(UIAction { [weak self] _ in self?.leavePrintings() }, for: .touchUpInside)

        // The builder appends to the bar and never searches; only Search does.
        builderView.onAdd = { [weak self] clause in self?.add(clause) }
        builderView.onSearch = { [weak self] in self?.commitSearch() }

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
                    self.persistResults()
                }
            }
        }
        resultsView.onScrollSettled = { [weak self] in self?.rememberPosition() }
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
        let allowed = hasFullAccess
        let changes = {
            self.buildingStack.isHidden = mode != .building || !allowed
            self.browsingStack.isHidden = mode != .browsing
            self.typingStack.isHidden = mode != .typing
            self.searchBar.isEditing = mode == .typing
            self.backButton.isHidden = mode != .browsing || self.printings == nil
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
        backButton.isHidden = !allowed || mode != .browsing || printings == nil
        buildingStack.isHidden = !allowed || mode != .building
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
            query.insert(text)
            queryChanged()
        case .deleteBackward:
            query.deleteBackward()
            queryChanged()
        case .submit:
            commitSearch()
        case .advanceToNextInputMode:
            advanceToNextInputMode()
        case .showBuilder:
            apply(mode: .building, animated: true)
        }
    }

    /// A clause from the builder joins the bar after a space. Nothing is sent:
    /// the user may want another clause first. Card text and "Other…" end at
    /// the operator, so the QWERTY opens with the caret where the words go.
    private func add(_ clause: QueryClause) {
        query.appendTerm(clause.syntax, caretFromEnd: clause.caretFromEnd)
        queryChanged()
        if clause.handsOffToKeyboard {
            apply(mode: .typing, animated: true)
        }
    }

    /// Keystrokes only edit the bar. Nothing is sent until the return key:
    /// the name-suggestion strip that used to fire `/cards/autocomplete` here
    /// was dropped for the syntax row, so there is no request to debounce.
    private func queryChanged() {
        searchBar.query = query.text
        searchBar.caret = query.caret
        builderView.canSearch = !query.text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func commitSearch() {
        let current = query.text
        printings = nil
        guard !current.trimmingCharacters(in: .whitespaces).isEmpty else {
            SavedSearch.clear()
            showEmptyState()
            return
        }
        apply(mode: .browsing, animated: true)
        SavedSearch.remember(query: current, printings: nil)
        runSearch(current)
    }

    /// A typed query, sorted the way the user chose in the app. A query that
    /// says `order:` itself keeps its own; the client drops the parameter.
    private func runSearch(_ query: String) {
        let order = preferences.order
        let direction = preferences.direction
        Task { await pipeline.search(query, order: order, direction: direction) }
    }

    /// The pill's clear button empties the bar and forgets the search; it
    /// never changes what is under the bar. The QWERTY stays up while typing
    /// (the sliders key is the way to the builder), the builder stays while
    /// building, and from the grid it opens the QWERTY: an empty bar over
    /// results means a new search is coming.
    private func clearQuery() {
        query = QueryBuffer()
        queryChanged()
        printings = nil
        gridBeforePrintings = nil
        pager = nil
        resultsView.show([])
        SavedSearch.clear()
        if mode == .browsing {
            apply(mode: .typing, animated: true)
        }
        Task {
            await SavedResults.shared.clear()
            await pipeline.cancel()
        }
    }

    /// Every printing of a card, newest first. Commander players care which
    /// art they send. Reached by holding a card. The pill keeps the query the
    /// user typed; the floating Back button returns to it.
    private func showPrintings(of card: Card) {
        if printings == nil {
            gridBeforePrintings = (pager, resultsView.cards, resultsView.firstVisibleIndex ?? 0)
        }
        printings = card.name
        backButton.isHidden = false
        toast.show("All printings of \(card.name)")
        SavedSearch.remember(query: query.text, printings: card.name)
        Task { await pipeline.searchExact(name: card.name) }
    }

    /// Back from the printings view to whatever filled the grid before it.
    /// The grid kept from before comes back as it was; after a keyboard
    /// rebuild there is none, and the query is run again.
    private func leavePrintings() {
        printings = nil
        backButton.isHidden = true
        SavedSearch.remember(query: query.text, printings: nil)
        Task { await pipeline.drop() }
        if let kept = gridBeforePrintings {
            gridBeforePrintings = nil
            pager = kept.pager
            resultsView.show(kept.cards, scrollTo: kept.firstVisible)
            SavedSearch.rememberPosition(kept.firstVisible)
            persistResults()
            return
        }
        let current = query.text
        if current.isEmpty {
            showEmptyState()
        } else {
            runSearch(current)
        }
    }

    /// Note where the grid is, for the next keyboard rebuild.
    private func rememberPosition() {
        guard !query.isEmpty || printings != nil, let index = resultsView.firstVisibleIndex else { return }
        SavedSearch.rememberPosition(index)
    }

    /// Write everything the pager has loaded to disk for the saved search.
    private func persistResults() {
        guard let pager, let saved = SavedSearch.load() else { return }
        resultsSequence += 1
        let sequence = resultsSequence
        Task {
            let snapshot = await pager.snapshot
            await SavedResults.shared.store(snapshot, id: saved.resultsID, sequence: sequence)
        }
    }

    /// The host rebuilds the keyboard on every dismissal, and pasting a copied
    /// card dismisses it, so the last search is re-run rather than lost.
    private func restoreLastSearch() {
        guard let saved = SavedSearch.load() else {
            showEmptyState()
            return
        }
        query = QueryBuffer(saved.query)
        queryChanged()
        printings = saved.printings
        apply(mode: .browsing, animated: false)
        resultsView.show(.loading)
        Task { [weak self] in
            let stored = await SavedResults.shared.load(id: saved.resultsID)
            guard let self else { return }
            if let stored {
                pager = ResultsPager(client: client, firstPage: stored)
                resultsView.show(stored.data, scrollTo: saved.firstVisible)
            } else if let name = saved.printings {
                await pipeline.searchExact(name: name)
            } else {
                runSearch(saved.query)
            }
        }
    }

    // MARK: - Empty state

    /// Nothing to show: the builder. It replaced a grid of recently copied
    /// cards on 2026-09-23; building the next search is the better use of
    /// the room.
    private func showEmptyState() {
        pager = nil
        resultsView.show([])
        apply(mode: .building, animated: mode == .typing)
    }

    // MARK: - Copying

    /// The product: full-size scan to the pasteboard, toast, let the bytes go.
    /// Or, by preference, the card's Scryfall page or its name as text.
    private func copy(_ card: Card) {
        switch preferences.copyFormat {
        case .image:
            copyImage(of: card)
        case .link:
            guard let link = card.pageURL else { return }
            // Both representations, so apps that read only text still paste.
            UIPasteboard.general.setItems([[
                UTType.url.identifier: link,
                UTType.utf8PlainText.identifier: link.absoluteString,
            ]])
            toast.show("Link copied")
        case .text:
            // The printings view is where the printing matters; elsewhere
            // the name alone reads better in a chat.
            UIPasteboard.general.string = printings == nil ? card.name : card.decklistLine
            toast.show("Name copied")
        }
    }

    private func copyImage(of card: Card) {
        guard let url = card.imageURL(.normal) else { return }
        copyTask?.cancel()
        toast.show("Copying…")
        copyTask = Task { [weak self] in
            do {
                let data = try await ImageStore.shared.imageData(for: url)
                guard !Task.isCancelled else { return }
                UIPasteboard.general.setData(data, forPasteboardType: UTType.jpeg.identifier)
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
            persistResults()
        case .empty(let query):
            resultsView.show(.message("No cards match “\(query)”."))
        case .failure(let error, _):
            resultsView.show(.message(error.localizedDescription))
        }
    }
}
