"""Prints one release's entry from App/Resources/CHANGELOG.md.

Usage: changelog.py <version> markdown|html

Exits with an error if the version has no entry, so nothing is released without notes. HTML is what Sparkle's update
window shows before installing; Markdown is for the GitHub release.
"""

import html
import pathlib
import re
import sys

CHANGELOG = pathlib.Path(__file__).resolve().parent.parent / "App" / "Resources" / "CHANGELOG.md"


def changes(version):
    found, items = False, []
    for line in CHANGELOG.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped.startswith("## "):
            if found:
                break
            found = stripped[3:].strip() == version
        elif found and stripped.startswith("- "):
            items.append(stripped[2:])
        elif found and stripped and line.startswith(" ") and items:
            items[-1] += " " + stripped
    if not found or not items:
        sys.exit(f"CHANGELOG.md has no entry for {version}. Add a '## {version}' section with what changed.")
    return items


def main(version, form):
    items = changes(version)
    if form == "markdown":
        print("\n".join(f"- {item}" for item in items))
    elif form == "html":
        body = "".join(f"<li>{html.escape(item)}</li>" for item in items)
        print(f"<h2>What's new in Sesame {html.escape(version)}</h2><ul>{body}</ul>")
    else:
        sys.exit("Format must be markdown or html.")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
