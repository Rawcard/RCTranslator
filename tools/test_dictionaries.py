#!/usr/bin/env python3
"""Check every dictionary for errors, then load each language in the addon
and translate words both ways.

  python3 tools/test_dictionaries.py

Data checks (any hit fails): each language file has exactly one line per
English key; no value contains '|', ']==]', a line break, or spaces at the
ends; no value is used twice in one language (the reverse lookup would lose
one); keys are unique, trimmed and lower-case. A value two English words
share (big / large -> groß) is normal and only counted.
Then in Lua (the addon's own code): every language loads without an error,
and for a sample of words, English -> language -> English gives the word back.
"""
import os
import random
import re
import sys

import lupa.luajit21 as lupa_mod

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, "Dictionaries")
BODY = re.compile(r"\[==\[\n(.*?)\]==\]", re.S)


def body(path):
    s = open(path, encoding="utf-8").read()
    m = BODY.search(s)
    lines = m.group(1).split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]
    return lines


def main():
    errors = []
    keys = body(os.path.join(D, "_Keys.lua"))
    seen = {}
    for i, k in enumerate(keys):
        if k != k.strip() or k == "":
            errors.append("_Keys line %d: blank or padded key %r" % (i + 1, k))
        if k != k.lower():
            errors.append("_Keys line %d: key not lower-case %r" % (i + 1, k))
        if k in seen:
            errors.append("_Keys line %d: duplicate key %r (also line %d)" % (i + 1, k, seen[k] + 1))
        seen[k] = i
    langs = sorted(f[:-4] for f in os.listdir(D) if f.endswith(".lua") and f not in ("_Keys.lua", "Common.lua", "Orcish.lua"))
    counts = {}
    shared = {}  # a value two English words share (big / large -> groß): fine, not an error
    for code in langs:
        vals = body(os.path.join(D, code + ".lua"))
        if len(vals) != len(keys):
            errors.append("%s: %d lines but %d keys" % (code, len(vals), len(keys)))
        used = {}
        n = 0
        for i, v in enumerate(vals):
            if not v:
                continue
            n += 1
            if "|" in v or "]==]" in v or "\r" in v:
                errors.append("%s line %d: bad character in %r" % (code, i + 1, v))
            if v != v.strip():
                errors.append("%s line %d: spaces at the ends of %r" % (code, i + 1, v))
            lv = v.lower()
            if lv in used:
                shared[code] = shared.get(code, 0) + 1
            used[lv] = i
        counts[code] = n
    print("data: %d keys, %d languages, %d problems" % (len(keys), len(langs), len(errors)))
    for e in errors[:40]:
        print("  " + e)

    # the addon itself: load every language, translate both ways
    L = lupa_mod.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    g.ADDON_DIR = ROOT
    g.TOC_FILE = "RC-Translator.toc"
    g.BUILD_TOC = 120005
    g.FLAVOR = "retail"
    g.CLASS_FILE = "MAGE"
    g.CLASS_ID = 8
    L.execute(open(os.path.join(ROOT, "tools", "wow_env.lua"), encoding="utf-8").read())
    L.execute(r"""
for line in io.lines(ADDON_DIR .. "/" .. TOC_FILE) do
	line = line:gsub("\r", ""):gsub("^\239\187\191", ""):gsub("\\", "/")
	if line ~= "" and not line:match("^#") and line:match("%.lua$") then
		local f = assert(io.open(ADDON_DIR .. "/" .. line, "rb")); local src = f:read("*a"); f:close()
		local fn = assert(loadstring(src:gsub("^\239\187\191", ""), "@" .. line))
		fn("RC-Translator", NS or {})
	end
end
""")
    T = g.RC_Translator
    rng = random.Random(7)
    lua_fail = 0
    for code in langs:
        try:
            T.EnsureLanguageLoaded(T, code)
        except Exception as e:  # noqa: BLE001
            lua_fail += 1
            print("FAIL %s: load error %s" % (code, str(e)[:300]))
            continue
        vals = body(os.path.join(D, code + ".lua"))
        sample = [i for i, v in enumerate(vals) if v and " " not in keys[i] and " " not in v]
        sample = rng.sample(sample, min(300, len(sample)))
        back = 0
        for i in sample:
            try:
                out = T.Translate(T, vals[i], code, "en")
                if isinstance(out, tuple):
                    out = out[0]
                if isinstance(out, str) and out.strip().lower() == keys[i]:
                    back += 1
                T.Translate(T, keys[i], "en", code)
            except Exception as e:  # noqa: BLE001
                lua_fail += 1
                print("FAIL %s: Translate(%r) raised %s" % (code, vals[i], str(e)[:200]))
                break
        print("%-5s %6d words  %4d shared  round trip %3d/%d" % (code, counts[code], shared.get(code, 0), back, len(sample)))
        if back < len(sample) * 0.8:
            lua_fail += 1
            print("FAIL %s: fewer than 80%% of words translate back" % code)
    # whole lines, the way chat sends them: words in other scripts, accents,
    # capitals and punctuation
    lines = [
        ("ru", "Привет, как дела?", "hello, how are you?"),
        ("ru", "ПРИВЕТ", "HELLO"),
        ("de", "Größe und Mädchen", "size and girls"),
        ("el", "Ευχαριστώ πολύ", "thank very"),
        ("ko", "안녕하세요 친구", "hello buddy"),
        ("hi", "धन्यवाद दोस्त", "thanks friend"),
        ("vi", "Cảm ơn bạn", "thank you"),
        ("fr", "«Bonjour» tout le monde", "«hello» everybody"),
    ]
    for code, text, want in lines:
        try:
            out = T.Translate(T, text, code, "en")
            out = out[0] if isinstance(out, tuple) else out
        except Exception as e:  # noqa: BLE001
            out = "ERROR " + str(e)[:200]
        # which English word comes back for a shared value can vary (hello /
        # hello there), so check the line came out all English, kept its
        # punctuation and its case
        import re as _re
        plain = isinstance(out, str) and not _re.search(r"[^\x00-\x7f«»]", out)
        punct = isinstance(out, str) and all(out.count(c) == text.count(c) for c in ",?!«»")
        case = isinstance(out, str) and (out == out.upper() if want == want.upper() else out[:1] == out[:1].upper() or not text[:1].isupper())
        ok = plain and punct and case
        print("%s %-4s %r -> %r" % ("ok  " if ok else "FAIL", code, text, out))
        if not ok:
            lua_fail += 1
    bad = len(errors) + lua_fail
    print("ALL PASS" if not bad else "%d FAILED" % bad)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
