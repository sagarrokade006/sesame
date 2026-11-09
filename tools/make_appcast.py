"""Writes the update feed that installed copies of Sesame read.

Usage: make_appcast.py <version> <build> <signature> <length> <output path>
"""

import sys
from email.utils import formatdate
from xml.sax.saxutils import escape, quoteattr

REPOSITORY = "https://github.com/sagarrokade006/sesame"


def main(version, build, signature, length, output):
    url = f"{REPOSITORY}/releases/download/v{version}/Sesame-{version}.dmg"
    notes = f"{REPOSITORY}/releases/tag/v{version}"
    feed = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Sesame</title>
    <item>
      <title>Version {escape(version)}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>{escape(notes)}</sparkle:fullReleaseNotesLink>
      <enclosure url={quoteattr(url)} length={quoteattr(length)} type="application/octet-stream" sparkle:edSignature={quoteattr(signature)}/>
    </item>
  </channel>
</rss>
"""
    with open(output, "w", encoding="utf-8") as file:
        file.write(feed)


if __name__ == "__main__":
    main(*sys.argv[1:6])
