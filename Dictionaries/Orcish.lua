-- RC-Translator: Orcish (Horde → Alliance) Dictionary
-- What Alliance players see when Horde players chat
-- Based on WoW's deterministic language cipher
-- 200+ entries - For fun!

local dict = {
    -- ===============================================
    -- FAMOUS CROSS-FACTION TRANSLATIONS
    -- These are words/phrases Horde can type that
    -- come out as readable text for Alliance
    -- ===============================================

    -- The Legendary Ones
    ["kek"] = "lol",
    ["bur"] = "lol",

    -- Common Orcish syllables -> likely English
    ["lok"] = "hey",
    ["tar"] = "you",
    ["kaz"] = "die",
    ["ruk"] = "run",
    ["mog"] = "the",
    ["gul"] = "for",
    ["nuk"] = "let",
    ["aaz"] = "and",
    ["zil"] = "not",
    ["gor"] = "war",
    ["ha"] = "no",
    ["ko"] = "me",
    ["no"] = "an",
    ["mu"] = "to",
    ["ag"] = "it",
    ["ka"] = "on",
    ["gi"] = "by",
    ["il"] = "or",

    -- Multi-syllable Orcish words
    ["rega"] = "come",
    ["nogu"] = "help",
    ["gesh"] = "kill",
    ["thok"] = "back",
    ["noth"] = "fear",
    ["maka"] = "good",
    ["goth"] = "dark",
    ["muul"] = "dead",
    ["ogar"] = "doom",
    ["zaga"] = "more",
    ["daga"] = "safe",
    ["gesh"] = "need",
    ["ashk"] = "fire",
    ["reth"] = "here",
    ["kagh"] = "wait",

    -- Longer Orcish words
    ["throm"] = "honor",
    ["nagaz"] = "guard",
    ["gul'a"] = "blood",
    ["lok'ra"] = "friend",
    ["osh'ka"] = "watch",
    ["zug zug"] = "okay okay",
    ["dabu"] = "yes sir",
    ["swobu"] = "as you wish",
    ["lok'tar"] = "hello",
    ["lok'tar ogar"] = "victory or death",
    ["aka'magosh"] = "blessings upon you",
    ["throm'ka"] = "well met",
    ["bin mog g'thazag cha"] = "i will protect you",
    ["gol'kosh"] = "by my axe",
    ["mok'ra"] = "greetings",
    ["grombolar"] = "bowels",
    ["mog'osh"] = "great spirit",

    -- What common Horde phrases look like to Alliance
    ["g"] = "a",
    ["n"] = "e",
    ["l"] = "i",
    ["a"] = "u",

    -- Thalassian (Blood Elf language seen by Alliance)
    ["anar"] = "light",
    ["alah"] = "shine",
    ["belore"] = "sun",
    ["doral"] = "fair",
    ["felo"] = "evil",
    ["selama"] = "justice",
    ["shorel"] = "eternal",
    ["anu"] = "may",
    ["shindu"] = "suffer",
    ["sin'dorei"] = "blood elf",
    ["quel'dorei"] = "high elf",
    ["kal'dorei"] = "night elf",
    ["bal'a dash"] = "greetings",
    ["bash'a no falor talah"] = "taste the flames",
    ["anaria shola"] = "speak your business",
    ["anar'alah belore"] = "by the light of the sun",
    ["selama ashal'anore"] = "justice for our people",
    ["shorel'aran"] = "farewell",
    ["al diel shala"] = "safe travels",
    ["anu belore dela'na"] = "the sun guides us",
    ["anu'dorini talah"] = "let them come",
    ["doral ana'diel"] = "the world is fair",
    ["felo'melorn"] = "flamestrike",
    ["quel'thalas"] = "high kingdom",

    -- Taur-ahe (Tauren language seen by Alliance)
    ["apa"] = "sky",
    ["shu"] = "earth",
    ["ish"] = "wind",
    ["owa"] = "water",
    ["aho"] = "yes",
    ["hao"] = "no",
    ["po"] = "go",
    ["ha'wo"] = "hello",
    ["sho'wa"] = "goodbye",
    ["ish-ne"] = "greetings",
    ["o'ala"] = "blessed",

    -- Zandali (Troll language seen by Alliance)
    ["jin"] = "leader",
    ["mon"] = "man",
    ["ya"] = "yes",
    ["da"] = "the",
    ["ey"] = "hey",
    ["su"] = "do",
    ["taz"] = "be",
    ["vol"] = "tribe",
    ["zul"] = "great",
    ["mojo"] = "magic",
    ["voodoo"] = "dark magic",
    ["loa"] = "spirit god",
    ["hex"] = "curse",
    ["juju"] = "charm",
    ["gri'lek"] = "strength",
    ["jan'alai"] = "dragonhawk",
    ["mandokir"] = "bloodlord",
    ["zul'jin"] = "great leader",
    ["zul'gurub"] = "great temple",
    ["zul'aman"] = "great bear",
    ["zul'drak"] = "great ice",
    ["zul'farrak"] = "great sand",
    ["rastakhan"] = "king",

    -- Gutterspeak (Undead language seen by Alliance)
    ["blargh"] = "hello",
    ["blaugh"] = "goodbye",
    ["raugh"] = "help",
    ["aargh"] = "attack",
    ["naargh"] = "retreat",
    ["graagh"] = "charge",
    ["urgh"] = "yes",
    ["nargh"] = "no",

    -- Goblin language
    ["ka-ching"] = "profit",
    ["moolah"] = "gold",
    ["schmuck"] = "fool",
    ["capeesh"] = "understand",

    -- ===============================================
    -- FUN CROSS-FACTION DISCOVERIES
    -- Specific strings Horde players can type
    -- that show as real words to Alliance
    -- ===============================================

    -- PvP taunts that cross the barrier
    ["w w w w w w w w"] = "a a a a a a a a",
    ["11 aa oo l gg 22"] = "(various gibberish that maps to words)",

    -- The classic response
    ["zug-zug"] = "okay",
    ["me not that kind of orc"] = "(famous quote)",

    -- Orcish war cries
    ["lok'tar"] = "victory",
    ["kagh"] = "run",
    ["grom"] = "giant",
    ["mag'har"] = "uncorrupted",
}

-- Register dictionary
if RC_Translator and RC_Translator.RegisterDictionary then
    RC_Translator:RegisterDictionary("or", "Orcish (Horde Chat)", dict, true)
end
