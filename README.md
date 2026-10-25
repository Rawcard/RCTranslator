# RC-Translator

Real-language chat translator for World of Warcraft. Highlights foreign words in chat, adds a clickable **[T]** to translate a line, and can show everything translated in its own chat tab. 38 languages, packed dictionaries that load only when used.

Works on Retail (Midnight), MoP Classic, Cata, Wrath, TBC Anniversary, Classic Era and WoW Forever. On Retail and WoW Forever the game can hide chat text from addons (in instances during combat, for example); those lines are left as they are.

Type `/rct` in game for the options and commands.

Maintained by **Raw Card**.

## Tests

`pip install lupa && python3 tools/test_clients.py` loads the addon on a simulated copy of every client and runs chat through it, including hidden chat on Retail and WoW Forever. It runs on every push.

## Releasing (for the maintainer)

1. Update `## Version` in both `.toc` files and put the notes in `CHANGELOG.md`.
2. On GitHub: **Releases** → **Draft a new release** → **Choose a tag** → type `v` plus the version (for example `v3.4.63`) → **Create new tag on publish** → **Publish release**.
3. The **Package and release** job (Actions tab) builds the zip, attaches it to the release, and uploads it to CurseForge (project `1462550`). It needs the `CF_API_KEY` secret (Settings → Secrets and variables → Actions).
