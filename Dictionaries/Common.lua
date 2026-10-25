-- RC-Translator: Common (Alliance → Horde) Dictionary
-- What Horde players see when Alliance players chat
-- Based on WoW's deterministic language cipher
-- 150+ entries - For fun!

local dict = {
    -- ===============================================
    -- FAMOUS CROSS-FACTION TRANSLATIONS
    -- These are words/phrases Alliance can type that
    -- come out as readable text for Horde
    -- ===============================================

    -- The Legendary One
    ["bur"] = "lol",

    -- Common syllables -> likely English
    ["an"] = "at",
    ["lo"] = "my",
    ["lu"] = "we",
    ["me"] = "so",
    ["ne"] = "of",
    ["re"] = "in",
    ["se"] = "up",
    ["ko"] = "am",
    ["far"] = "the",
    ["dor"] = "was",
    ["gol"] = "can",
    ["are"] = "our",
    ["mos"] = "all",
    ["ver"] = "now",
    ["ash"] = "old",

    -- Multi-syllable Common words
    ["alas"] = "come",
    ["dath"] = "here",
    ["neph"] = "call",
    ["ansi"] = "stop",
    ["reli"] = "save",
    ["tara"] = "wait",
    ["arri"] = "flee",
    ["mush"] = "push",
    ["dana"] = "give",

    -- Common phrases
    ["a"] = "i",
    ["e"] = "a",
    ["i"] = "e",

    -- Darnassian (Night Elf language seen by Horde)
    ["ande"] = "may",
    ["ash"] = "it",
    ["ala"] = "the",
    ["tor"] = "let",
    ["shan're"] = "honored",
    ["thero'shan"] = "honored teacher",
    ["ishnu"] = "good",
    ["alah"] = "fortune",
    ["dal"] = "be",
    ["nordrassil"] = "crown of the heavens",
    ["teldrassil"] = "crown of the earth",
    ["elune-adore"] = "elune be with you",
    ["ishnu-alah"] = "good fortune",
    ["ishnu-dal-dieb"] = "good fortune to your family",
    ["shan'do"] = "honored teacher",
    ["thero'shan"] = "honored student",
    ["andu-falah-dor"] = "let balance be restored",
    ["tor ilisar'thera'nal"] = "let our enemies beware",
    ["ash karath"] = "do it",
    ["bandu thoribas"] = "prepare to fight",
    ["fandu-dath-belore"] = "the enemy approaches",

    -- Draenei language seen by Horde
    ["archenon"] = "greetings",
    ["poros"] = "blessings",
    ["eredun"] = "language",
    ["naaru"] = "holy being",
    ["draenei"] = "exiled ones",
    ["shattrath"] = "dwelling of light",
    ["man'ari"] = "corrupted ones",

    -- Gnomish language seen by Horde
    ["whirr"] = "hello",
    ["click"] = "yes",
    ["buzz"] = "no",
    ["beep"] = "help",
    ["zap"] = "attack",

    -- Dwarvish language seen by Horde
    ["modan"] = "mountain",
    ["anvilmar"] = "anvil home",
    ["khaz"] = "great",
    ["modan"] = "mountain",
    ["khaz modan"] = "great mountain",
    ["thane"] = "lord",

    -- ===============================================
    -- ALLIANCE WAR CRIES & PHRASES
    -- ===============================================
    ["for khaz modan"] = "for the mountain",

    -- ===============================================
    -- CROSS-FACTION UNIVERSAL EMOTES
    -- These work regardless of language!
    -- ===============================================
    ["/wave"] = "waves at you",
    ["/salute"] = "salutes you",
    ["/rude"] = "makes a rude gesture",
    ["/spit"] = "spits on the ground",
    ["/laugh"] = "laughs",
    ["/cry"] = "cries",
    ["/chicken"] = "clucks like a chicken",
    ["/train"] = "choo choo!",
    ["/flex"] = "flexes muscles",
    ["/dance"] = "dances",
    ["/bow"] = "bows",
    ["/charge"] = "starts to charge",
    ["/roar"] = "roars with rage",
    ["/threaten"] = "threatens you",
    ["/cower"] = "cowers in fear",
    ["/beg"] = "begs",
    ["/grovel"] = "grovels on the ground",
    ["/flirt"] = "flirts",
    ["/silly"] = "tells a joke",
    ["/no"] = "shakes head no",
    ["/yes"] = "nods yes",
    ["/point"] = "points",
    ["/goodbye"] = "waves goodbye",
    ["/hello"] = "greets you",
    ["/thank"] = "thanks you",
    ["/welcome"] = "welcomes you",
}

-- Register dictionary
if RC_Translator and RC_Translator.RegisterDictionary then
    RC_Translator:RegisterDictionary("co", "Common (Alliance Chat)", dict, true)
end
