import UIKit
import KeyboardCore

/// Emoji picker with an iOS-style search entry, horizontal catalogue browsing,
/// category shortcuts, and the standard keyboard controls along the bottom.
final class EmojiKeyboardView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onSelectEmoji: ((String) -> Void)?
    var onSearch: (() -> Void)?
    var onReturnToLetters: (() -> Void)?
    var onDelete: (() -> Void)?
    var onDeletePressBegan: (() -> Void)?
    private(set) var inputModeSwitchButton: UIButton?

    private let catalog: EmojiCatalog
    private let allItems: [EmojiItem]
    private let theme: KeyboardTheme
    private let gridLayout = UICollectionViewFlowLayout()
    private let grid: UICollectionView
    private let searchButton = UIButton(type: .system)
    private let categoryScroll = UIScrollView()
    private let categoryStack = UIStackView()
    private let footer = UIStackView()
    private var categoryButtons: [(section: Int?, button: UIButton)] = []
    private var selectedSection: Int?
    private var lastSize: CGSize = .zero
    private var backspaceHandler: EmojiBackspaceHandler?

    private var visibleItems: [EmojiItem] {
        guard let selectedSection, catalog.sections.indices.contains(selectedSection) else { return allItems }
        return catalog.sections[selectedSection].entries
    }

    init(catalog: EmojiCatalog, theme: KeyboardTheme, interfaceLanguage: InterfaceLanguage,
         needsInputModeSwitch: Bool) {
        self.catalog = catalog
        allItems = catalog.sections.flatMap(\.entries)
        self.theme = theme
        gridLayout.scrollDirection = .horizontal
        gridLayout.minimumLineSpacing = 3
        gridLayout.minimumInteritemSpacing = 2
        grid = UICollectionView(frame: .zero, collectionViewLayout: gridLayout)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configureSearch(interfaceLanguage: interfaceLanguage)
        configureGrid()
        configureCategoryBar(interfaceLanguage: interfaceLanguage)
        configureFooter(interfaceLanguage: interfaceLanguage, needsInputModeSwitch: needsInputModeSwitch)
        configureLayout()
        selectCategory(at: nil, scrollTab: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard abs(lastSize.width - grid.bounds.width) > 1 || abs(lastSize.height - grid.bounds.height) > 1 else { return }
        lastSize = grid.bounds.size
        gridLayout.invalidateLayout()
    }

    private func configureSearch(interfaceLanguage: InterfaceLanguage) {
        searchButton.translatesAutoresizingMaskIntoConstraints = false
        searchButton.contentHorizontalAlignment = .leading
        searchButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 11, bottom: 0, right: 10)
        searchButton.setImage(UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)), for: .normal)
        searchButton.setTitle("  " + GlassTypeText.translate("Поиск эмодзи", to: interfaceLanguage), for: .normal)
        searchButton.titleLabel?.font = .systemFont(ofSize: 14)
        searchButton.tintColor = theme.foreground.withAlphaComponent(0.76)
        searchButton.setTitleColor(theme.foreground.withAlphaComponent(0.76), for: .normal)
        searchButton.backgroundColor = theme.key.withAlphaComponent(0.48)
        searchButton.layer.cornerRadius = 13
        searchButton.layer.cornerCurve = .continuous
        searchButton.layer.borderWidth = 0.5
        searchButton.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        searchButton.accessibilityLabel = GlassTypeText.translate("Поиск эмодзи", to: interfaceLanguage)
        searchButton.addAction(UIAction { [weak self] _ in self?.onSearch?() }, for: .touchUpInside)
    }

    private func configureGrid() {
        backgroundColor = .clear
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.backgroundColor = .clear
        grid.dataSource = self
        grid.delegate = self
        grid.alwaysBounceHorizontal = true
        grid.showsHorizontalScrollIndicator = false
        grid.showsVerticalScrollIndicator = false
        grid.isDirectionalLockEnabled = true
        grid.contentInsetAdjustmentBehavior = .never
        grid.contentInset = UIEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
        grid.register(EmojiItemCell.self, forCellWithReuseIdentifier: EmojiItemCell.reuseIdentifier)
    }

    private func configureCategoryBar(interfaceLanguage: InterfaceLanguage) {
        categoryScroll.translatesAutoresizingMaskIntoConstraints = false
        categoryScroll.showsHorizontalScrollIndicator = false
        categoryScroll.alwaysBounceHorizontal = true
        categoryScroll.contentInsetAdjustmentBehavior = .never
        categoryStack.translatesAutoresizingMaskIntoConstraints = false
        categoryStack.axis = .horizontal
        categoryStack.alignment = .center
        categoryStack.spacing = 4
        categoryScroll.addSubview(categoryStack)
        NSLayoutConstraint.activate([
            categoryStack.leadingAnchor.constraint(equalTo: categoryScroll.contentLayoutGuide.leadingAnchor, constant: 3),
            categoryStack.trailingAnchor.constraint(equalTo: categoryScroll.contentLayoutGuide.trailingAnchor, constant: -3),
            categoryStack.topAnchor.constraint(equalTo: categoryScroll.frameLayoutGuide.topAnchor),
            categoryStack.bottomAnchor.constraint(equalTo: categoryScroll.frameLayoutGuide.bottomAnchor),
            categoryStack.heightAnchor.constraint(equalTo: categoryScroll.frameLayoutGuide.heightAnchor)
        ])

        let all = footerButton(image: "square.grid.3x3.fill")
        all.accessibilityLabel = GlassTypeText.translate("Все эмодзи", to: interfaceLanguage)
        all.accessibilityHint = GlassTypeText.translate("Показать эмодзи категории", to: interfaceLanguage)
        all.addAction(UIAction { [weak self] _ in self?.selectCategory(at: nil, scrollTab: true) }, for: .touchUpInside)
        all.widthAnchor.constraint(equalToConstant: 40).isActive = true
        categoryStack.addArrangedSubview(all)
        categoryButtons.append((nil, all))

        for (index, section) in catalog.sections.enumerated() {
            let button = footerButton(image: section.category.symbolName)
            button.accessibilityLabel = GlassTypeText.translate(section.category.titleKey, to: interfaceLanguage)
            button.accessibilityHint = GlassTypeText.translate("Показать эмодзи категории", to: interfaceLanguage)
            button.tag = index
            button.addTarget(self, action: #selector(categoryTapped(_:)), for: .touchUpInside)
            button.widthAnchor.constraint(equalToConstant: 40).isActive = true
            categoryStack.addArrangedSubview(button)
            categoryButtons.append((index, button))
        }
    }

    private func configureFooter(interfaceLanguage: InterfaceLanguage, needsInputModeSwitch: Bool) {
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.axis = .horizontal
        footer.alignment = .center
        footer.spacing = 3

        let letters = footerButton(title: "ABC")
        letters.accessibilityLabel = GlassTypeText.translate("Сменить на буквы", to: interfaceLanguage)
        letters.addAction(UIAction { [weak self] _ in self?.onReturnToLetters?() }, for: .touchUpInside)
        letters.widthAnchor.constraint(equalToConstant: 48).isActive = true
        footer.addArrangedSubview(letters)

        if needsInputModeSwitch {
            let systemKeyboard = footerButton(image: "keyboard")
            systemKeyboard.accessibilityLabel = GlassTypeText.translate("Другие системные клавиатуры", to: interfaceLanguage)
            systemKeyboard.widthAnchor.constraint(equalToConstant: 40).isActive = true
            inputModeSwitchButton = systemKeyboard
            footer.addArrangedSubview(systemKeyboard)
        }

        categoryScroll.heightAnchor.constraint(equalToConstant: 42).isActive = true
        categoryScroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        categoryScroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(categoryScroll)

        let delete = footerButton(image: "delete.left")
        delete.accessibilityLabel = GlassTypeText.translate("Удалить", to: interfaceLanguage)
        delete.widthAnchor.constraint(equalToConstant: 44).isActive = true
        footer.addArrangedSubview(delete)
        installBackspaceRepeat(on: delete, deleteLabel: GlassTypeText.translate("Удалить", to: interfaceLanguage))
    }

    private func configureLayout() {
        addSubview(searchButton)
        addSubview(grid)
        addSubview(footer)
        NSLayoutConstraint.activate([
            searchButton.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            searchButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            searchButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            searchButton.heightAnchor.constraint(equalToConstant: 36),
            grid.topAnchor.constraint(equalTo: searchButton.bottomAnchor, constant: 2),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            footer.heightAnchor.constraint(equalToConstant: 46)
        ])
    }

    private func footerButton(title: String? = nil, image: String? = nil) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        if let image {
            button.setImage(UIImage(systemName: image, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)), for: .normal)
        }
        button.tintColor = theme.foreground
        button.setTitleColor(theme.foreground, for: .normal)
        button.backgroundColor = theme.key.withAlphaComponent(0.54)
        button.layer.cornerRadius = 11
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 0.5
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        button.heightAnchor.constraint(equalToConstant: 38).isActive = true
        return button
    }

    @objc private func categoryTapped(_ sender: UIButton) {
        selectCategory(at: sender.tag, scrollTab: true)
    }

    private func selectCategory(at index: Int?, scrollTab: Bool) {
        if let index, !catalog.sections.indices.contains(index) { return }
        selectedSection = index
        for item in categoryButtons {
            let selected = item.section == index
            item.button.backgroundColor = theme.key.withAlphaComponent(selected ? 0.95 : 0.42)
            item.button.layer.borderColor = UIColor.white.withAlphaComponent(selected ? 0.25 : 0.08).cgColor
            item.button.accessibilityTraits = selected ? [.button, .selected] : .button
            if selected && scrollTab {
                let rect = item.button.convert(item.button.bounds, to: categoryScroll).insetBy(dx: -4, dy: 0)
                categoryScroll.scrollRectToVisible(rect, animated: true)
            }
        }
        grid.setContentOffset(.zero, animated: false)
        grid.reloadData()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        visibleItems.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiItemCell.reuseIdentifier, for: indexPath) as! EmojiItemCell
        let item = visibleItems[indexPath.item]
        cell.configure(item, color: theme.foreground)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard visibleItems.indices.contains(indexPath.item) else { return }
        onSelectEmoji?(visibleItems[indexPath.item].emoji)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        CGSize(width: 42, height: 42)
    }

    private func installBackspaceRepeat(on button: UIButton, deleteLabel: String) {
        backspaceHandler = EmojiBackspaceHandler(button: button, deleteLabel: deleteLabel,
                                                 onBegin: { [weak self] in
            self?.onDeletePressBegan?()
        }, onRepeat: { [weak self] in self?.onDelete?() })
    }
}

private final class EmojiItemCell: UICollectionViewCell {
    static let reuseIdentifier = "EmojiItemCell"
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 27)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.72
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            label.topAnchor.constraint(equalTo: contentView.topAnchor),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        contentView.layer.cornerRadius = 10
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.09, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.contentView.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.88, y: 0.88) : .identity
                self.contentView.backgroundColor = self.isHighlighted ? UIColor.white.withAlphaComponent(0.13) : .clear
            }
        }
    }

    func configure(_ item: EmojiItem, color: UIColor) {
        label.text = item.emoji
        label.textColor = color
        accessibilityLabel = item.name
        isAccessibilityElement = true
    }
}

private final class EmojiBackspaceHandler: NSObject {
    private weak var button: UIButton?
    private let idleColor: UIColor?
    private let onBegin: () -> Void
    private let onRepeat: () -> Void
    private var timer: Timer?
    private var active = false
    private var heldSince: TimeInterval = 0

    init(button: UIButton, deleteLabel: String, onBegin: @escaping () -> Void, onRepeat: @escaping () -> Void) {
        self.button = button
        idleColor = button.backgroundColor
        self.onBegin = onBegin
        self.onRepeat = onRepeat
        super.init()
        button.addTarget(self, action: #selector(begin), for: .touchDown)
        button.addTarget(self, action: #selector(end), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        button.accessibilityCustomActions = [UIAccessibilityCustomAction(name: deleteLabel) { [weak self] _ in self?.onBegin(); return true }]
    }

    @objc private func begin() {
        stop()
        active = true
        heldSince = ProcessInfo.processInfo.systemUptime
        button?.isHighlighted = true
        UIView.animate(withDuration: 0.06, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.button?.backgroundColor = self.button?.backgroundColor?.withAlphaComponent(0.9)
        }
        onBegin()
        schedule(BackspaceRepeat.initialDelay)
    }

    @objc private func end() {
        stop()
        button?.isHighlighted = false
        UIView.animate(withDuration: 0.1, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.button?.backgroundColor = self.idleColor
        }
    }

    private func schedule(_ interval: TimeInterval) {
        let next = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            guard let self, self.active else { return }
            self.onRepeat()
            self.schedule(BackspaceRepeat.interval(heldFor: ProcessInfo.processInfo.systemUptime - self.heldSince))
        }
        timer = next
        RunLoop.main.add(next, forMode: .common)
    }

    private func stop() {
        active = false
        timer?.invalidate()
        timer = nil
    }

    deinit { timer?.invalidate() }
}
