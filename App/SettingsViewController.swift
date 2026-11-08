import UIKit
import KeyboardCore

final class SettingsViewController: UITableViewController {
    private var settings = KeyboardSettings.load()

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func t(_ source: String) -> String { GlassTypeText.translate(source, to: settings.interfaceLanguage) }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "GlassType"
        tableView.keyboardDismissMode = .interactive
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 52
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 4 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { [1, 25, 3, 1][section] }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Подключение", "Настройки", "Языки — минимум один", "Проверка ввода"].indices.contains(section)
            ? t(["Подключение", "Настройки", "Языки — минимум один", "Проверка ввода"][section]) : nil
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 { return t("Добавьте GlassType в настройках клавиатуры iOS. Полный доступ нужен только для общих настроек приложения и синхронизации личного словаря. Ввод, автозамена, словарные подсказки и локальная адаптация работают в расширении без него.") }
        if section == 1 { return t("Удерживайте глобус или эмодзи-клавишу для настроек клавиатуры. Без полного доступа параметры и словарь хранятся отдельно в расширении. Подсказки используют только локальные агрегированные счётчики; текст и история касаний не записываются.") }
        return nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        if indexPath.section == 0 {
            cell.textLabel?.text = t("Открыть настройки iOS")
            cell.accessoryType = .disclosureIndicator
        }
        if indexPath.section == 1 {
            let labels = ["Тема", "Подсказки", "Заглавная в начале предложения", "Виброотклик", "Символы удержанием", "Метки на клавишах", "Задержка удержания", "Автозамена", "Компактные клавиши", "Отображение символа при нажатии", "Двойной пробел → точка", "Свайп удаления слова", "Свайп-ввод слов", "Адаптация касаний", "Показать зоны касаний", "Лицензии словарей", "Заменить глобус на эмодзи", "Разрешить нецензурные слова в подсказках и автозамене", "Высота клавиатуры", "Визуальная ширина клавиш", "Предсказание следующего слова", "Локальное обучение подсказок", "Язык интерфейса", "Затухание росчерка", "Толщина росчерка"]
            guard labels.indices.contains(indexPath.row) else { return cell }
            cell.textLabel?.text = t(labels[indexPath.row])
            cell.textLabel?.numberOfLines = indexPath.row == 17 ? 3 : ((indexPath.row == 2 || indexPath.row >= 9) ? 2 : 1)
            switch indexPath.row {
            case 15:
                cell.accessoryType = .disclosureIndicator
            case 0:
                let control = UISegmentedControl(items: [t("Авто"), t("Светлая"), t("Тёмная")])
                control.selectedSegmentIndex = ThemeChoice.allCases.firstIndex(of: settings.theme) ?? 0
                control.addTarget(self, action: #selector(themeChanged(_:)), for: .valueChanged)
                cell.accessoryView = control
            case 3:
                let control = UISegmentedControl(items: HapticChoice.allCases.map { t($0.title) })
                control.selectedSegmentIndex = HapticChoice.allCases.firstIndex(of: settings.haptics) ?? 0
                control.addTarget(self, action: #selector(hapticsChanged(_:)), for: .valueChanged)
                cell.accessoryView = control
            case 6:
                let control = UISegmentedControl(items: ["0,25 с", "0,4 с", "0,6 с"])
                control.selectedSegmentIndex = settings.holdDelay < 0.325 ? 0 : (settings.holdDelay < 0.5 ? 1 : 2)
                control.addTarget(self, action: #selector(delayChanged(_:)), for: .valueChanged)
                cell.accessoryView = control
            case 22:
                let control = UISegmentedControl(items: InterfaceLanguage.allCases.map(\.shortTitle))
                control.selectedSegmentIndex = InterfaceLanguage.allCases.firstIndex(of: settings.interfaceLanguage) ?? 0
                control.accessibilityLabel = t("Язык интерфейса")
                control.addTarget(self, action: #selector(interfaceLanguageChanged(_:)), for: .valueChanged)
                cell.accessoryView = control
            case 18, 19, 23, 24:
                let slider = UISlider(frame: CGRect(x: 0, y: 0, width: 132, height: 32))
                slider.tag = indexPath.row
                if indexPath.row == 18 {
                    slider.minimumValue = 0.92; slider.maximumValue = 1.10
                    slider.value = Float(settings.keyboardHeightScale)
                } else if indexPath.row == 19 {
                    slider.minimumValue = 0.84; slider.maximumValue = 1.12
                    slider.value = Float(settings.visualKeyWidthScale)
                } else if indexPath.row == 23 {
                    slider.minimumValue = 0.1; slider.maximumValue = 0.8
                    slider.value = Float(settings.glideTrailFadeDuration)
                } else {
                    slider.minimumValue = 2; slider.maximumValue = 10
                    slider.value = Float(settings.glideTrailWidth)
                }
                slider.accessibilityLabel = t(labels[indexPath.row])
                let display = sliderDisplayValue(slider.value, row: indexPath.row)
                slider.accessibilityValue = display
                slider.addTarget(self, action: #selector(sizeChanged(_:)), for: .valueChanged)
                cell.detailTextLabel?.text = display
                cell.accessoryView = slider
            default:
                let control = UISwitch(); control.tag = indexPath.row
                switch indexPath.row {
                case 1: control.isOn = settings.suggestions
                case 2: control.isOn = settings.autoCapitalization
                case 4: control.isOn = settings.extraSymbols
                case 7: control.isOn = settings.autoCorrection
                case 8: control.isOn = settings.compactKeys
                case 9: control.isOn = settings.showKeyPreview
                case 10: control.isOn = settings.doubleSpacePeriod
                case 11: control.isOn = settings.swipeDeleteWord
                case 12: control.isOn = settings.glideTyping
                case 13: control.isOn = settings.touchAdaptationEnabled
                case 14: control.isOn = settings.debugTouchZones
                case 16: control.isOn = settings.emojiKeyEnabled
                case 17: control.isOn = settings.allowProfanitySuggestions
                case 20: control.isOn = settings.nextWordPrediction
                case 21: control.isOn = settings.personalizationEnabled
                default: control.isOn = settings.symbolHints
                }
                control.addTarget(self, action: #selector(toggle(_:)), for: .valueChanged)
                cell.accessoryView = control
            }
        }
        if indexPath.section == 2 {
            let language = KeyboardLanguage.allCases[indexPath.row]
            cell.textLabel?.text = language.title
            cell.accessoryType = settings.languages.contains(language) ? .checkmark : .none
        }
        if indexPath.section == 3 {
            let field = UITextField(); field.placeholder = t("Введите текст…"); field.borderStyle = .roundedRect
            field.translatesAutoresizingMaskIntoConstraints = false; cell.contentView.addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                field.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                field.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
                field.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12)
            ])
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0, let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        if indexPath.section == 1 && indexPath.row == 15 {
            let page = UIViewController(); page.title = t("Лицензии словарей")
            let text = UITextView(); text.isEditable = false; text.dataDetectorTypes = []
            text.font = .preferredFont(forTextStyle: .body); text.adjustsFontForContentSizeCategory = true
            text.text = OfflineLexicon.licenseNotice; text.backgroundColor = .systemBackground
            page.view = text; navigationController?.pushViewController(page, animated: true)
        }
        if indexPath.section == 2 {
            let language = KeyboardLanguage.allCases[indexPath.row]
            settings.languages = EnabledKeyboardLanguages.setting(language, enabled: !settings.languages.contains(language), in: settings.languages)
            settings.save(); tableView.reloadSections(IndexSet(integer: 2), with: .none)
        }
    }

    @objc private func themeChanged(_ control: UISegmentedControl) { settings.theme = ThemeChoice.allCases[control.selectedSegmentIndex]; settings.save() }
    @objc private func hapticsChanged(_ control: UISegmentedControl) { settings.haptics = HapticChoice.allCases[control.selectedSegmentIndex]; settings.save() }
    @objc private func delayChanged(_ control: UISegmentedControl) { settings.holdDelay = [0.25, 0.4, 0.6][control.selectedSegmentIndex]; settings.save() }
    @objc private func interfaceLanguageChanged(_ control: UISegmentedControl) {
        guard InterfaceLanguage.allCases.indices.contains(control.selectedSegmentIndex) else { return }
        settings.interfaceLanguage = InterfaceLanguage.allCases[control.selectedSegmentIndex]
        settings.save(); tableView.reloadData()
    }
    @objc private func sizeChanged(_ control: UISlider) {
        let value = Double(control.value)
        if control.tag == 18 { settings.keyboardHeightScale = KeyboardSizing.heightScale(value) }
        else if control.tag == 19 { settings.visualKeyWidthScale = KeyboardSizing.visualWidthScale(value) }
        else if control.tag == 23 { settings.glideTrailFadeDuration = KeyboardSettings.clampedGlideTrailFadeDuration(value) }
        else if control.tag == 24 { settings.glideTrailWidth = KeyboardSettings.clampedGlideTrailWidth(value) }
        let display = sliderDisplayValue(control.value, row: control.tag)
        control.accessibilityValue = display
        if let cell = tableView.cellForRow(at: IndexPath(row: control.tag, section: 1)) {
            cell.detailTextLabel?.text = display
        }
        settings.save()
    }
    private func sliderDisplayValue(_ value: Float, row: Int) -> String {
        switch row {
        case 23: return String(format: "%.2f с", value)
        case 24: return "\(Int(value.rounded())) pt"
        default: return "\(Int((value * 100).rounded()))%"
        }
    }
    @objc private func toggle(_ control: UISwitch) {
        switch control.tag {
        case 1: settings.suggestions = control.isOn
        case 2: settings.autoCapitalization = control.isOn
        case 4: settings.extraSymbols = control.isOn
        case 7: settings.autoCorrection = control.isOn
        case 8: settings.compactKeys = control.isOn
        case 9: settings.showKeyPreview = control.isOn
        case 10: settings.doubleSpacePeriod = control.isOn
        case 11: settings.swipeDeleteWord = control.isOn
        case 12: settings.glideTyping = control.isOn
        case 13: settings.touchAdaptationEnabled = control.isOn
        case 14: settings.debugTouchZones = control.isOn
        case 16: settings.emojiKeyEnabled = control.isOn
        case 17: settings.allowProfanitySuggestions = control.isOn
        case 20: settings.nextWordPrediction = control.isOn
        case 21: settings.personalizationEnabled = control.isOn
        default: settings.symbolHints = control.isOn
        }
        settings.save()
    }
}
