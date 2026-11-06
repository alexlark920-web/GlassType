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
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 4 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { [1, 3, 3, 1][section] }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { ["Подключение", "Настройки", "Языки — минимум один", "Проверка ввода"][section] }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? "Настройки → Основные → Клавиатура → Клавиатуры → Новые клавиатуры → GlassType. Для общих настроек может потребоваться полный доступ. Клавиатура работает и без него, не отправляет текст и не использует сеть." : nil
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        if indexPath.section == 0 { cell.textLabel?.text = "Открыть настройки iOS"; cell.accessoryType = .disclosureIndicator }
        if indexPath.section == 1 {
            cell.textLabel?.text = ["Тема", "Подсказки", "Заглавная после точки"][indexPath.row]
            if indexPath.row == 0 {
                let control = UISegmentedControl(items: ["Авто", "Светлая", "Тёмная"])
                control.selectedSegmentIndex = ThemeChoice.allCases.firstIndex(of: settings.theme) ?? 0
                control.addTarget(self, action: #selector(themeChanged(_:)), for: .valueChanged)
                cell.accessoryView = control
            } else {
                let control = UISwitch(); control.tag = indexPath.row
                control.isOn = indexPath.row == 1 ? settings.suggestions : settings.autoCapitalization
                control.addTarget(self, action: #selector(toggle(_:)), for: .valueChanged); cell.accessoryView = control
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
        if indexPath.section == 2 {
            let language = KeyboardLanguage.allCases[indexPath.row]
            if settings.languages.contains(language) { if settings.languages.count > 1 { settings.languages.removeAll { $0 == language } } }
            else { settings.languages.append(language) }
            settings.save(); tableView.reloadSections(IndexSet(integer: 2), with: .none)
        }
    }
    @objc private func themeChanged(_ control: UISegmentedControl) { settings.theme = ThemeChoice.allCases[control.selectedSegmentIndex]; settings.save() }
    @objc private func toggle(_ control: UISwitch) {
        if control.tag == 1 { settings.suggestions = control.isOn } else { settings.autoCapitalization = control.isOn }
        settings.save()
    }
}
