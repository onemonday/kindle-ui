-- Plugin strings deliberately fall back to English for every non-Russian locale.
local ru = {
    ["Quick actions panel"] = "Панель быстрых действий",
    ["Home"] = "Домой",
    ["Library"] = "Библиотека", ["Book"] = "Книга", ["Skim document"] = "Быстрое пролистывание",
    ["Left"] = "Слева", ["Right"] = "Справа", ["Value"] = "Значение",
    ["Current value"] = "Текущее значение", ["Default value"] = "По умолчанию",
    ["Set as default"] = "Сделать по умолчанию", ["Not set"] = "Не задано",
    ["Apply"] = "Применить", ["Done"] = "Готово", ["Clear"] = "Очистить",
    ["Range"] = "Диапазон", ["About this setting"] = "Об этой настройке",
    ["Back"] = "Назад",
    ["Hold: set as default"] = "Удержание: по умолчанию",
    ["Fine adjustment"] = "Точная настройка",
    ["Enable top drawer"] = "Включить верхнюю шторку",
    ["Top drawer settings"] = "Настройки верхней шторки",
    ["Enable bottom drawer"] = "Включить нижнюю шторку",
    ["Bottom drawer settings"] = "Настройки нижней шторки",
    ["Remember last tab"] = "Запоминать последнюю вкладку",
    ["Font"] = "Шрифт", ["Layout"] = "Макет", ["Page"] = "Страница", ["More"] = "Ещё",
    ["KOReader settings"] = "Параметры KOReader", ["Set value"] = "Задать значение",
    ["Dim background"] = "Затемнять фон",
    ["Full refresh on open and close"] = "Полное обновление при открытии и закрытии",
    ["Kindle Drawer"] = "Шторка Kindle",
    ["Open drawer"] = "Открыть шторку",
    ["Replace top menu"] = "Открывать вместо верхнего меню",
    ["Drawer buttons"] = "Кнопки шторки",
    ["Header title"] = "Заголовок шторки",
    ["Save"] = "Сохранить", ["Cancel"] = "Отмена",
    ["Wi-Fi"] = "Wi-Fi", ["Dark Mode"] = "Тёмный режим",
    ["Sync"] = "Синхронизация", ["Frontlight"] = "Подсветка",
    ["All Settings"] = "Все настройки", ["Power"] = "Питание",
    ["SSH server"] = "SSH-сервер", ["Brightness"] = "Яркость",
    ["Warmth"] = "Теплота", ["On"] = "Вкл.", ["Off"] = "Выкл.",
    ["Restart"] = "Перезапуск", ["Sleep"] = "Сон",
    ["Exit KOReader"] = "Выйти из KOReader",
    ["Open a book and enable KOSync."] = "Откройте книгу и включите KOSync.",
    ["Enable the SSH plugin in KOReader first."] = "Сначала включите SSH-плагин в KOReader.",
    ["SSH server is already running."] = "SSH-сервер уже запущен.",
}
local M = {}
function M.language()
    local lang = G_reader_settings:readSetting("language") or "en"
    return (lang == "ru" or lang:match("^ru[_%-]")) and "ru" or "en"
end
function M.tr(text)
    return M.language() == "ru" and ru[text] or text
end
return M
