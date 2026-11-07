import UIKit
import KeyboardCore
final class SettingsViewController: UITableViewController {
    private var settings = KeyboardSettings.load()
    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "GlassType"
        tableView.keyboardDismissMode = .interactive
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 52
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 4 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { [1, 16, 3, 1][section] }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { ["Подключение", "Настройки", "Языки — минимум один", "Проверка ввода"][section] }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 { return "Настройки → Основные → Клавиатура → Клавиатуры → Новые клавиатуры → GlassType. Для общих настроек может потребоваться полный доступ. Клавиатура работает и без него, не отправляет текст и не использует сеть." }
        if section == 1 { return "Если общие настройки недоступны после установки через SideStore, удерживайте глобус в ряду клавиш. Локальные настройки имеют приоритет. Личный словарь и исключения редактируются в меню клавиатуры. Виброотклик зависит также от iOS и устройства; при отсутствии отклика проверьте полный доступ и системные настройки тактильных сигналов. Отключение доп. символов сохраняет языковые варианты: ё, ґ, диакритику." }
        return nil
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        if indexPath.section == 0 { cell.textLabel?.text = "Открыть настройки iOS"; cell.accessoryType = .disclosureIndicator }
        if indexPath.section == 1 {
            cell.textLabel?.text = ["Тема", "Подсказки", "Заглавная в начале предложения", "Виброотклик", "Символы удержанием", "Метки на клавишах", "Задержка удержания", "Автозамена", "Компактные клавиши", "Отображение символа при нажатии", "Двойной пробел → точка", "Свайп удаления слова", "Свайп-ввод слов", "Адаптация касаний", "Показать зоны касаний", "Лицензии словарей"][indexPath.row]
            cell.textLabel?.numberOfLines = (indexPath.row == 2 || indexPath.row >= 9) ? 2 : 1
            switch indexPath.row {
            case 15: cell.accessoryType = .disclosureIndicator
            case 0:
                let control = UISegmentedControl(items: ["Авто", "Светлая", "Тёмная"])
                control.selectedSegmentIndex = ThemeChoice.allCases.firstIndex(of: settings.theme) ?? 0
                control.addTarget(self, action: #selector(themeChanged(_:)), for: .valueChanged)
                cell.accessoryView = control
            case 3:
                let control = UISegmentedControl(items: HapticChoice.allCases.map(\.title))
                control.selectedSegmentIndex = HapticChoice.allCases.firstIndex(of: settings.haptics) ?? 0
                control.addTarget(self, action: #selector(hapticsChanged(_:)), for: .valueChanged)
                cell.accessoryView = control
            case 6:
                let control = UISegmentedControl(items: ["0,25 с", "0,4 с", "0,6 с"])
                control.selectedSegmentIndex = settings.holdDelay < 0.325 ? 0 : (settings.holdDelay < 0.5 ? 1 : 2)
                control.addTarget(self, action: #selector(delayChanged(_:)), for: .valueChanged)
                cell.accessoryView = control
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
            let field = UITextField(); field.placeholder = "Введите текст…"; field.borderStyle = .roundedRect
            field.translatesAutoresizingMaskIntoConstraints = false; cell.contentView.addSubview(field)
            NSLayoutConstraint.activate([field.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor), field.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor), field.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12), field.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12)])
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0, let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        if indexPath.section == 1 && indexPath.row == 15 {
            let page = UIViewController(); page.title = "Лицензии словарей"
            let text = UITextView(); text.isEditable = false; text.dataDetectorTypes = []
            text.font = .preferredFont(forTextStyle: .body); text.adjustsFontForContentSizeCategory = true
            text.text = OfflineLexicon.licenseNotice; text.backgroundColor = .systemBackground
            page.view = text; navigationController?.pushViewController(page, animated: true)
        }
        if indexPath.section == 2 {
            let language = KeyboardLanguage.allCases[indexPath.row]
            if settings.languages.contains(language) { if settings.languages.count > 1 { settings.languages.removeAll { $0 == language } } }
            else { settings.languages.append(language) }
            settings.save(); tableView.reloadSections(IndexSet(integer: 2), with: .none)
        }
    }
    @objc private func themeChanged(_ control: UISegmentedControl) { settings.theme = ThemeChoice.allCases[control.selectedSegmentIndex]; settings.save() }
    @objc private func hapticsChanged(_ control: UISegmentedControl) {
        settings.haptics = HapticChoice.allCases[control.selectedSegmentIndex]; settings.save()
    }
    @objc private func delayChanged(_ control: UISegmentedControl) {
        settings.holdDelay = [0.25, 0.4, 0.6][control.selectedSegmentIndex]; settings.save()
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
        default: settings.symbolHints = control.isOn
        }
        settings.save()
    }
}
