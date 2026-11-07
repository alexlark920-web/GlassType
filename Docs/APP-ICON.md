# Иконка GlassType

В линии 1.7 build 15 добавлены два варианта по предоставленному пользователем
образцу: тёмное графитовое стекло и светлое ледяное стекло, одинаковая клавиатурная
композиция 5 / 4 / (клавиша, пробел, клавиша), мягкий синий блик. Изображения
созданы генератором изображений; светлая версия подготовлена из тёмной с сохранением
геометрии. Техническая подготовка включает масштабирование в 1024×1024 и RGB PNG.

Файлы:

- `App/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png` — основной вариант Any.
- `App/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png` — luminosity/dark.
- `AppIcon.appiconset/Contents.json` — системные варианты одного значка.
- `GlassType.xcodeproj/project.pbxproj` — каталог в ресурсах приложения,
  `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon` в Debug и Release.

Оба PNG непрозрачные, без внешних полей и заранее вырезанных углов. Системная маска
применяется iOS. Иконки находятся в основном приложении; клавиатурное расширение
не загружает их при наборе. Клавиатурные Swift-файлы и алгоритмы в этом обновлении
не менялись.

На iOS с поддержкой вариантов Home Screen пользователь выбирает светлый,
тёмный или автоматический вид в оформлении домашнего экрана. Это отдельная
настройка от темы клавиатуры. Старые системы используют основной вариант.
Поставлены растровые изображения для asset catalog, без слоёв Icon Composer.

Проверка структуры контролирует включение каталога, варианты, размер и отсутствие
alpha-канала. Сборка Xcode компилирует каталог; упаковка IPA проверяет основную
иконку в Info.plist, fallback-файлы и тёмное appearance в Assets.car. Фактический
результат конкретной сборки — в [CHECK_RESULTS.txt](CHECK_RESULTS.txt).

Build 15 проверена в [GitHub Actions](https://github.com/alexlark920-web/GlassType/actions/runs/42338499265):
143 теста без ошибок, сборка симулятора и архив устройства успешны; проверка
`Assets.car` подтвердила тёмный вариант. Переключение на физическом iPhone пока
не проверено. [Скачать ZIP с unsigned IPA](https://github.com/alexlark920-web/GlassType/actions/runs/42338499265/artifacts/13560024333).

Руководства Apple: [Configuring your app icon using an asset catalog](https://developer.apple.com/documentation/xcode/configuring-your-app-icon),
[App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons),
[Customize apps and widgets on the Home Screen](https://support.apple.com/guide/iphone/iph385473442/ios).
