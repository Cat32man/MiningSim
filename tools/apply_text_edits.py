"""Writes the edits from text_edits.json (made by the in-game Text editor) back into the scripts.

Each edit names the file, the line it was on, the original literal and the new text, all in
source form. The literal is looked for on that line first, then on the nearest line holding
it (code may have moved since). Applied edits are removed from text_edits.json; anything that
couldn't be found is left there and reported.

    python tools/apply_text_edits.py [--dry-run]
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
EDITS = ROOT / "text_edits.json"
SEARCH_WINDOW = 200  # lines either side of the recorded line


def escape_bare_quotes(text: str, quote: str) -> str:
    """A quote typed into the editor must be escaped to stay inside the literal."""
    return re.sub(r'(?<!\\)' + re.escape(quote), '\\\\' + quote, text)


def apply(edit: dict, files: dict) -> str | None:
    path = ROOT / edit["file"].removeprefix("res://")
    if path not in files:
        with open(path, encoding="utf-8", newline="") as f:  # keep the file's line endings
            files[path] = f.read().split("\n")
    lines = files[path]
    want = edit["line"] - 1
    order = sorted(range(max(0, want - SEARCH_WINDOW), min(len(lines), want + SEARCH_WINDOW + 1)),
                   key=lambda i: abs(i - want))
    for i in order:
        for q in ('"', "'"):
            lit = q + edit["original"] + q
            if lit in lines[i]:
                new = q + escape_bare_quotes(edit["text"], q) + q
                lines[i] = lines[i].replace(lit, new, 1)
                return f"{path.relative_to(ROOT)}:{i + 1}"
    return None


def main() -> None:
    dry = "--dry-run" in sys.argv
    data = json.loads(EDITS.read_text(encoding="utf-8"))
    files: dict = {}
    left = []
    applied = 0
    for e in data.get("edits", []):
        where = apply(e, files)
        if where:
            print(f"  {where}: {e['original']!r} -> {e['text']!r}")
            applied += 1
        else:
            print(f"  NOT FOUND {e['file']}:{e['line']}: {e['original']!r}")
            left.append(e)
    if dry:
        print("(dry run, nothing written)")
        return
    for path, lines in files.items():
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write("\n".join(lines))
    data["edits"] = left
    EDITS.write_text(json.dumps(data, indent="\t", ensure_ascii=False), encoding="utf-8")
    print(f"Applied {applied}, {len(left)} not found (kept in text_edits.json).")


if __name__ == "__main__":
    main()
