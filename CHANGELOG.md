# RC-Translator 3.4.64

- **Words in other alphabets now translate.** Russian, Ukrainian, Bulgarian, Serbian, Greek, Arabic, Hebrew, Persian, Hindi and Korean words weren't recognised as words at all, so lines in those languages came through untranslated. Words with accents (é, ü, ő, ș, ę, ầ...) were cut in half at the accent, so many French, German, Polish, Czech, Hungarian, Turkish, Romanian and Vietnamese words were missed too. Both are fixed.
- Capitalised and ALL-CAPS words in those languages are recognised ("Привет", "ПРИВЕТ"), and the translation keeps the capitals.
- Punctuation such as ¿ ¡ « » „ “ ” … and the Arabic, Hindi and Chinese commas and full stops no longer sticks to the word next to it, and a phrase is no longer matched across punctuation (so "«Bonjour» tout le monde" keeps its »).
- When two English words share a translation, translating back now always picks the same, more common one.
- **About 3,400 more everyday words** (such as "because", "already", "hungry", "weekend", "hospital", "providers", "survivors"), in all 38 languages. Persian, Hebrew, Arabic, Thai and Hindi also got about 2,400 words each that the other languages already had. Every language now knows over 25,000 words.
- A new test checks every dictionary (one line per word, no stray characters) and translates a sample of words from every language back to English.

## RC-Translator 3.4.63

- **Wrath Titan Reforged** (client 3.80) is listed as supported again, so CurseForge offers this version to Titan Reforged players. Checked in the Chinese game language.
- Release jobs updated to GitHub's newer Node 24 actions (no more Node.js 20 warning).

## RC-Translator 3.4.62

- RC-Translator now lives on GitHub. Releases are built and uploaded to CurseForge automatically.
- **Retail and WoW Forever:** the game can hide chat text from addons (for example in instances during combat). Those lines now pass through untouched instead of risking errors; everything else is translated as before.
- **WoW Forever:** its own TOC file for the Forever client.
- Updated the supported client versions (Retail 12.1, TBC Anniversary 2.5.6, Classic Era 1.15.9).
