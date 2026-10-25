--[[
    RC-Translator: Language Registry

    Every dictionary now lives in THIS folder as a packed string blob rather
    than as a separate LoadOnDemand addon. WoW only scans Interface/AddOns one
    level deep, so LoadOnDemand would have meant 34 sibling folders. Instead the
    dictionaries ship as flat strings -- cheap -- and are only expanded into
    real Lua tables (forward + reverse) when a language is actually used.
]]

local T = RC_Translator
if not T then return end

T.LanguageRegistry = {
    { code = "en", name = "English" },
    { code = "ar", name = "Arabic (العربية)" },
    { code = "bg", name = "Bulgarian (Български)" },
    { code = "zh", name = "Simplified Chinese (简体中文)" },
    { code = "hr", name = "Croatian (Hrvatski)" },
    { code = "cs", name = "Czech (Čeština)" },
    { code = "da", name = "Danish (Dansk)" },
    { code = "nl", name = "Dutch (Nederlands)" },
    { code = "tl", name = "Filipino (Tagalog)" },
    { code = "fi", name = "Finnish (Suomi)" },
    { code = "fr", name = "French (Français)" },
    { code = "de", name = "German (Deutsch)" },
    { code = "el", name = "Greek (Ελληνικά)" },
    { code = "he", name = "Hebrew (עברית)" },
    { code = "hi", name = "Hindi (हिन्दी)" },
    { code = "hu", name = "Hungarian (Magyar)" },
    { code = "id", name = "Indonesian (Bahasa Indonesia)" },
    { code = "it", name = "Italian (Italiano)" },
    { code = "ja", name = "Japanese (日本語)" },
    { code = "ko", name = "Korean (한국어)" },
    { code = "esMX", name = "Latin American Spanish (Español latino)" },
    { code = "ms", name = "Malay (Bahasa Melayu)" },
    { code = "no", name = "Norwegian (Norsk)" },
    { code = "pl", name = "Polish (Polski)" },
    { code = "pt", name = "Portuguese (Português — Portugal)" },
    { code = "ptBR", name = "Brazilian Portuguese (Português do Brasil)" },
    { code = "ro", name = "Romanian (Română)" },
    { code = "ru", name = "Russian (Русский)" },
    { code = "es", name = "Spanish (Español)" },
    { code = "sv", name = "Swedish (Svenska)" },
    { code = "th", name = "Thai (ไทย)" },
    { code = "zhTW", name = "Traditional Chinese (繁體中文)" },
    { code = "tr", name = "Turkish (Türkçe)" },
    { code = "uk", name = "Ukrainian (Українська)" },
    { code = "vi", name = "Vietnamese (Tiếng Việt)" },
    { code = "sk", name = "Slovak (Slovenčina)" },
    { code = "sl", name = "Slovenian (Slovenščina)" },
    { code = "ca", name = "Catalan (Català)" },
    { code = "sr", name = "Serbian (Srpski)" },
    { code = "fa", name = "Persian (فارسی)" },
}

for _, info in ipairs(T.LanguageRegistry) do
    if not T.Languages[info.code] then
        T.Languages[info.code] = {
            code = info.code, name = info.name, loaded = false,
            dictionary = nil, reverse = nil, wordCount = 0, hidden = false,
        }
    end
end
