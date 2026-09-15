-- Plugin strings deliberately fall back to English for every non-Russian locale.
local ru = {
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
