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

    override func numberOfSections(in tableView: UITableView) -> Int { 5 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { [1, 26, 3, 1, 3][section] }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Подключение", "Настройки", "Языки — минимум один", "Проверка ввода", "Диагностика"].indices.contains(section)
            ? t(["Подключение", "Настройки", "Языки — минимум один", "Проверка ввода", "Диагностика"][section]) : nil
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 { return t("Добавьте GlassType в настройках клавиатуры iOS. Полный доступ нужен только для общих настроек приложения и синхронизации личного словаря. Ввод, автозамена, словарные подсказки и локальная адаптация работают в расширении без него.") }
        if section == 1 { return t("Нажмите на шестерёнку рядом с глобусом или эмодзи-клавишей, чтобы открыть это приложение. Для синхронизации настроек включите «Полный доступ» в настройках iOS; без него iOS изолирует данные расширения. Подсказки используют только локальные агрегированные счётчики; текст и история касаний не записываются.") }
        if section == 4 { return t("Сбор выключен по умолчанию. При включении сохраняются только агрегированные счётчики, ранги подсказок, время расчёта и сводка адаптации касаний. Текст, слова и сырые координаты не записываются; данные не отправляются по сети. Для передачи статистики клавиатуры приложению нужен «Полный доступ».") }
        return nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        if indexPath.section == 0 {
            cell.textLabel?.text = t("Открыть настройки iOS")
            cell.accessoryType = .disclosureIndicator
        }
        if indexPath.section == 1 {
            let labels = ["Тема", "Подсказки", "Заглавная в начале предложения", "Виброотклик", "Символы удержанием", "Метки на клавишах", "Задержка удержания", "Автозамена", "Компактные клавиши", "Отображать ряд цифр", "Отображение символа при нажатии", "Двойной пробел → точка", "Свайп удаления слова", "Свайп-ввод слов", "Адаптация касаний", "Показать зоны касаний", "Лицензии словарей", "Заменить глобус на эмодзи", "Разрешить нецензурные слова в подсказках и автозамене", "Высота клавиатуры", "Визуальная ширина клавиш", "Предсказание следующего слова", "Локальное обучение подсказок", "Язык интерфейса", "Затухание росчерка", "Толщина росчерка"]
            guard labels.indices.contains(indexPath.row) else { return cell }
            cell.textLabel?.text = t(labels[indexPath.row])
            cell.textLabel?.numberOfLines = indexPath.row == 18 ? 3 : ((indexPath.row == 2 || indexPath.row >= 9) ? 2 : 1)
            cell.textLabel?.lineBreakMode = .byWordWrapping
            switch indexPath.row {
            case 16:
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
            case 23:
                let control = UISegmentedControl(items: InterfaceLanguage.allCases.map(\.shortTitle))
                control.selectedSegmentIndex = InterfaceLanguage.allCases.firstIndex(of: settings.interfaceLanguage) ?? 0
                control.accessibilityLabel = t("Язык интерфейса")
                control.addTarget(self, action: #selector(interfaceLanguageChanged(_:)), for: .valueChanged)
                cell.accessoryView = control
            case 19, 20, 24, 25:
                let slider = UISlider(frame: CGRect(x: 0, y: 0, width: 132, height: 32))
                slider.tag = indexPath.row
                if indexPath.row == 19 {
                    slider.minimumValue = 0.92; slider.maximumValue = 1.10
                    slider.value = Float(settings.keyboardHeightScale)
                } else if indexPath.row == 20 {
                    slider.minimumValue = 0.84; slider.maximumValue = 1.12
                    slider.value = Float(settings.visualKeyWidthScale)
                } else if indexPath.row == 24 {
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
                case 9: control.isOn = settings.showNumberRow
                case 10: control.isOn = settings.showKeyPreview
                case 11: control.isOn = settings.doubleSpacePeriod
                case 12: control.isOn = settings.swipeDeleteWord
                case 13: control.isOn = settings.glideTyping
                case 14: control.isOn = settings.touchAdaptationEnabled
                case 15: control.isOn = settings.debugTouchZones
                case 17: control.isOn = settings.emojiKeyEnabled
                case 18: control.isOn = settings.allowProfanitySuggestions
                case 21: control.isOn = settings.nextWordPrediction
                case 22: control.isOn = settings.personalizationEnabled
                default: control.isOn = settings.symbolHints
                }
                control.accessibilityLabel = t(labels[indexPath.row])
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
        if indexPath.section == 4 {
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = t("Сбор локальной статистики")
                let control = UISwitch()
                control.isOn = settings.telemetryEnabled
                control.accessibilityLabel = t("Сбор локальной статистики")
                control.addTarget(self, action: #selector(telemetryChanged(_:)), for: .valueChanged)
                cell.accessoryView = control
            case 1:
                cell.textLabel?.text = t("Экспортировать статистику")
                cell.accessoryType = .disclosureIndicator
            default:
                cell.textLabel?.text = t("Сбросить статистику")
                cell.textLabel?.textColor = .systemRed
            }
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0, let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        if indexPath.section == 1 && indexPath.row == 16 {
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
        if indexPath.section == 4 {
            if indexPath.row == 1 { exportStatistics() }
            if indexPath.row == 2 { confirmStatisticsReset() }
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
        if control.tag == 19 { settings.keyboardHeightScale = KeyboardSizing.heightScale(value) }
        else if control.tag == 20 { settings.visualKeyWidthScale = KeyboardSizing.visualKeyWidthScale(value) }
        else if control.tag == 24 { settings.glideTrailFadeDuration = KeyboardSettings.clampedGlideTrailFadeDuration(value) }
        else if control.tag == 25 { settings.glideTrailWidth = KeyboardSettings.clampedGlideTrailWidth(value) }
        let display = sliderDisplayValue(control.value, row: control.tag)
        control.accessibilityValue = display
        if let cell = tableView.cellForRow(at: IndexPath(row: control.tag, section: 1)) {
            cell.detailTextLabel?.text = display
        }
        settings.save()
    }
    private func sliderDisplayValue(_ value: Float, row: Int) -> String {
        switch row {
        case 24: return String(format: "%.2f с", value)
        case 25: return "\(Int(value.rounded())) pt"
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
        case 9: settings.showNumberRow = control.isOn
        case 10: settings.showKeyPreview = control.isOn
        case 11: settings.doubleSpacePeriod = control.isOn
        case 12: settings.swipeDeleteWord = control.isOn
        case 13: settings.glideTyping = control.isOn
        case 14: settings.touchAdaptationEnabled = control.isOn
        case 15: settings.debugTouchZones = control.isOn
        case 17: settings.emojiKeyEnabled = control.isOn
        case 18: settings.allowProfanitySuggestions = control.isOn
        case 21: settings.nextWordPrediction = control.isOn
        case 22: settings.personalizationEnabled = control.isOn
        default: settings.symbolHints = control.isOn
        }
        settings.save()
    }

    @objc private func telemetryChanged(_ control: UISwitch) {
        settings.telemetryEnabled = control.isOn
        settings.save()
    }

    private func exportStatistics() {
        do {
            guard let snapshot = try KeyboardTelemetryStorage.read().snapshot else {
                showStatisticsAlert(title: t("Нет статистики для экспорта"),
                                    message: t("Включите сбор, разрешите полный доступ и воспользуйтесь клавиатурой, затем повторите экспорт."))
                return
            }
            let bundle = Bundle.main
            let document = KeyboardTelemetryExport(
                snapshot: snapshot,
                appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
                buildNumber: bundle.infoDictionary?["CFBundleVersion"] as? String,
                operatingSystemVersion: UIDevice.current.systemVersion
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("GlassType-Statistics-\(UUID().uuidString).json")
            try data.write(to: url, options: .atomic)

            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.completionWithItemsHandler = { [weak self] _, _, _, error in
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    NSLog("GlassType telemetry export file could not be removed: %@", String(describing: error))
                }
                if let error {
                    NSLog("GlassType telemetry share failed: %@", String(describing: error))
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.showStatisticsAlert(
                            title: self.t("Не удалось экспортировать статистику"),
                            message: self.t("Попробуйте ещё раз. Если ошибка повторится, перезапустите приложение.")
                        )
                    }
                }
            }
            if let popover = activity.popoverPresentationController {
                popover.sourceView = tableView
                if let cell = tableView.cellForRow(at: IndexPath(row: 1, section: 4)) {
                    popover.sourceRect = tableView.convert(cell.bounds, from: cell)
                } else {
                    popover.sourceRect = CGRect(x: tableView.bounds.midX, y: tableView.bounds.midY, width: 1, height: 1)
                }
            }
            present(activity, animated: true)
        } catch KeyboardTelemetryStorageError.sharedContainerUnavailable {
            showStatisticsAlert(title: t("Нужен полный доступ"),
                                message: t("Включите «Полный доступ» для GlassType в настройках iOS, чтобы прочитать статистику клавиатуры."))
        } catch {
            showStatisticsAlert(title: t("Не удалось экспортировать статистику"),
                                message: t("Попробуйте ещё раз. Если ошибка повторится, перезапустите приложение."))
            NSLog("GlassType telemetry export failed: %@", String(describing: error))
        }
    }

    private func confirmStatisticsReset() {
        let alert = UIAlertController(title: t("Сбросить статистику?"),
                                      message: t("Все собранные агрегированные показатели будут удалены."),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: t("Отмена"), style: .cancel))
        alert.addAction(UIAlertAction(title: t("Сбросить статистику"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            do {
                try KeyboardTelemetryStorage.reset()
            } catch {
                self.showStatisticsAlert(title: self.t("Не удалось сбросить статистику"),
                                         message: self.t("Попробуйте ещё раз."))
                NSLog("GlassType telemetry reset failed: %@", String(describing: error))
            }
        })
        present(alert, animated: true)
    }

    private func showStatisticsAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: t("Готово"), style: .default))
        present(alert, animated: true)
    }
}
