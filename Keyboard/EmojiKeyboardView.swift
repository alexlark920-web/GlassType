import UIKit
import KeyboardCore

final class EmojiKeyboardView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onSelectEmoji: ((String) -> Void)?
    var onReturnToLetters: (() -> Void)?
    var onDelete: (() -> Void)?
    private(set) var inputModeSwitchButton: UIButton?

    private let catalog: EmojiCatalog
    private let theme: KeyboardTheme
    private let gridLayout = UICollectionViewFlowLayout()
    private let grid: UICollectionView
    private let categoryScroll = UIScrollView()
    private let categoryStack = UIStackView()
    private let footer = UIStackView()
    private var categoryButtons: [EmojiCategory: UIButton] = [:]
    private var selectedSection = 0
    private var lastWidth: CGFloat = 0
    private var backspaceHandler: EmojiBackspaceHandler?

    init(catalog: EmojiCatalog, theme: KeyboardTheme, interfaceLanguage: InterfaceLanguage,
         needsInputModeSwitch: Bool) {
        self.catalog = catalog
        self.theme = theme
        gridLayout.scrollDirection = .vertical
        gridLayout.minimumLineSpacing = 2
        gridLayout.minimumInteritemSpacing = 2
        grid = UICollectionView(frame: .zero, collectionViewLayout: gridLayout)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configureGrid()
        configureCategoryBar(interfaceLanguage: interfaceLanguage)
        configureFooter(interfaceLanguage: interfaceLanguage, needsInputModeSwitch: needsInputModeSwitch)
        configureLayout()
        selectCategory(at: 0, scrollTab: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard abs(lastWidth - grid.bounds.width) > 1 else { return }
        lastWidth = grid.bounds.width
        gridLayout.invalidateLayout()
    }

    private func configureGrid() {
        backgroundColor = .clear
        grid.backgroundColor = .clear
        grid.dataSource = self
        grid.delegate = self
        grid.alwaysBounceVertical = true
        grid.showsVerticalScrollIndicator = false
        grid.contentInsetAdjustmentBehavior = .never
        grid.contentInset = UIEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
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

        for (index, section) in catalog.sections.enumerated() {
            let button = footerButton(image: section.category.symbolName)
            button.accessibilityLabel = GlassTypeText.translate(section.category.titleKey, to: interfaceLanguage)
            button.accessibilityHint = GlassTypeText.translate("Показать эмодзи категории", to: interfaceLanguage)
            button.tag = index
            button.addTarget(self, action: #selector(categoryTapped(_:)), for: .touchUpInside)
            button.widthAnchor.constraint(equalToConstant: 40).isActive = true
            categoryStack.addArrangedSubview(button)
            categoryButtons[section.category] = button
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
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        addSubview(footer)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: topAnchor),
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

    private func selectCategory(at index: Int, scrollTab: Bool) {
        guard catalog.sections.indices.contains(index) else { return }
        selectedSection = index
        for (category, button) in categoryButtons {
            let selected = category == catalog.sections[index].category
            button.backgroundColor = theme.key.withAlphaComponent(selected ? 0.95 : 0.42)
            button.layer.borderColor = UIColor.white.withAlphaComponent(selected ? 0.25 : 0.08).cgColor
            button.accessibilityTraits = selected ? [.button, .selected] : .button
            if selected && scrollTab {
                let rect = button.convert(button.bounds, to: categoryScroll).insetBy(dx: -4, dy: 0)
                categoryScroll.scrollRectToVisible(rect, animated: true)
            }
        }
        grid.setContentOffset(.zero, animated: false)
        grid.reloadData()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        catalog.sections.indices.contains(selectedSection) ? catalog.sections[selectedSection].entries.count : 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiItemCell.reuseIdentifier, for: indexPath) as! EmojiItemCell
        let item = catalog.sections[selectedSection].entries[indexPath.item]
        cell.configure(item, color: theme.foreground)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard catalog.sections.indices.contains(selectedSection),
              catalog.sections[selectedSection].entries.indices.contains(indexPath.item) else { return }
        onSelectEmoji?(catalog.sections[selectedSection].entries[indexPath.item].emoji)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let availableWidth = max(1, collectionView.bounds.width - collectionView.contentInset.left - collectionView.contentInset.right)
        let columns = max(5, min(18, Int(availableWidth / 42)))
        let spacing = CGFloat(columns - 1) * gridLayout.minimumInteritemSpacing
        let width = floor((availableWidth - spacing) / CGFloat(columns))
        return CGSize(width: width, height: 42)
    }

    private func installBackspaceRepeat(on button: UIButton, deleteLabel: String) {
        backspaceHandler = EmojiBackspaceHandler(button: button, deleteLabel: deleteLabel) { [weak self] in self?.onDelete?() }
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
    private let onDelete: () -> Void
    private var timer: Timer?
    private var repeated = false
    private var active = false
    private var heldSince: TimeInterval = 0

    init(button: UIButton, deleteLabel: String, onDelete: @escaping () -> Void) {
        self.onDelete = onDelete
        super.init()
        button.addTarget(self, action: #selector(begin), for: .touchDown)
        button.addTarget(self, action: #selector(end), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        button.accessibilityCustomActions = [UIAccessibilityCustomAction(name: deleteLabel) { [weak self] _ in self?.onDelete(); return true }]
    }

    @objc private func begin() {
        stop()
        active = true
        repeated = false
        heldSince = ProcessInfo.processInfo.systemUptime
        schedule(BackspaceRepeat.initialDelay)
    }

    @objc private func end() {
        guard active else { return }
        let wasRepeated = repeated
        stop()
        if !wasRepeated { onDelete() }
    }

    private func schedule(_ interval: TimeInterval) {
        let next = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            guard let self, self.active else { return }
            self.repeated = true
            self.onDelete()
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
