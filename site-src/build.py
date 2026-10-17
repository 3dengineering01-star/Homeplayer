"""Builds the OwnMedia site into site/: plain HTML, CSS and pictures, ready to upload as is.

    python site-src/build.py

Everything that is said on many pages, or that the owner still has to give, is set ONCE below
(SETTINGS): the site's address, the contact email, the company, the links to Google Play and to
the Windows installer. Change it there and build again; every page follows.

Pages are in site-src/pages/: each file is the middle of one page (between the header and the
footer), with a few lines on top:

    title: Download
    description: One sentence for search engines and link previews.
    path: download/
    ---
    <section>…</section>

In a page, {{root}} is the way back to the site's root from that page ("./", "../", "../../"),
so that every link inside the site is relative; {{icon:film}} is an icon; {{NAME}} is one of the
SETTINGS or of the snippets made from them (see snippets()).

Another language later: the same pages in site-src/pages/ru/ with "lang: ru" and paths under ru/.
No third-party code: Python's standard library only.
"""

import hashlib
import html
import re
import shutil
import sys
import zipfile
from datetime import date
from pathlib import Path

# ---------------------------------------------------------------------------------------------
# SETTINGS: the owner's answers. Empty means "not given yet": the site shows a placeholder and
# the build prints a reminder.
# ---------------------------------------------------------------------------------------------

SETTINGS = {
    # The site's full address, without a slash at the end. Used only where a full address is a
    # must: sitemap.xml, robots.txt, link previews (Open Graph) and the canonical address.
    "SITE_URL": "https://educonsalt.com",
    # Email for privacy questions and support.
    "CONTACT_EMAIL": "",
    # The company, letter for letter as in the Google payments profile and D-U-N-S.
    "COMPANY_NAME": "SIA “Mroya”",
    "COMPANY_REG": "50203370261",
    # TO CHECK with the owner: taken from a directory site, not from the register.
    "COMPANY_ADDRESS": "Ganību dambis 20A, Rīga, Latvia",
    "COMPANY_COUNTRY": "Latvia",
    # The app in Google Play; empty while it is not published (the site offers the beta instead).
    "PLAY_URL": "",
    # Where OwnMediaSetup.exe is downloaded from; empty while there is no public link.
    "INSTALLER_URL": "",
    # The Jellyfin plugin catalogue for NAS, Docker and Linux (jellyfin-repo/manifest.json).
    "CATALOG_URL": "https://raw.githubusercontent.com/3dengineering01-star/Homeplayer/main/jellyfin-repo/manifest.json",
    # The plugin's public source code (GPL).
    "SOURCE_URL": "https://github.com/3dengineering01-star/Homeplayer",
}

SRC = Path(__file__).resolve().parent
OUT = SRC.parent / "site"
PAGES = SRC / "pages"
STATIC = SRC / "static"

# ---------------------------------------------------------------------------------------------
# Icons: 24 x 24, drawn with a line, in the colour of the text around them.
# ---------------------------------------------------------------------------------------------

_I = {
    "film": '<rect x="3" y="4" width="18" height="16" rx="3"/><path d="M7 4v16M17 4v16M3 9h4M3 15h4M17 9h4M17 15h4"/>',
    "music": '<path d="M9 18V5l11-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="17" cy="16" r="3"/>',
    "globe": '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
    "photo": '<rect x="3" y="4" width="18" height="16" rx="3"/><circle cx="9" cy="10" r="2"/><path d="m21 16-5-5-9 9"/>',
    "users": '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M16 4.5a3.5 3.5 0 0 1 0 7M18 14a6.5 6.5 0 0 1 3.5 6"/>',
    "download": '<path d="M12 3v12M7 10l5 5 5-5M4 20h16"/>',
    "car": '<path d="M5 16V11l2-5h10l2 5v5"/><path d="M3 16h18v3H3zM5 11h14"/><circle cx="7.5" cy="16" r="1"/><circle cx="16.5" cy="16" r="1"/>',
    "shield": '<path d="M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6z"/><path d="m9 12 2 2 4-4"/>',
    "check": '<path d="m5 12 5 5 9-10"/>',
    "check-circle": '<circle cx="12" cy="12" r="9"/><path d="m8 12 3 3 5-6"/>',
    "left": '<path d="m15 5-7 7 7 7"/>',
    "right": '<path d="m9 5 7 7-7 7"/>',
    "menu": '<path d="M4 7h16M4 12h16M4 17h16"/>',
    "windows": '<path d="M3 5.5 10.5 4.5v7H3zM12.5 4.2 21 3v8.5h-8.5zM3 12.5h7.5v7L3 18.5zM12.5 12.5H21V21l-8.5-1.2z"/>',
    "nas": '<rect x="4" y="3" width="16" height="18" rx="2.5"/><path d="M8 7h8M8 11h8"/><circle cx="12" cy="16.5" r="1.5"/>',
    "play": '<path d="M7 4.5v15l12-7.5z"/>',
    "tv": '<rect x="3" y="5" width="18" height="12" rx="2"/><path d="M8 21h8M12 17v4"/>',
    "link": '<path d="M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1 1"/><path d="M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1-1"/>',
    "mail": '<rect x="3" y="5" width="18" height="14" rx="2.5"/><path d="m4 7 8 6 8-6"/>',
    "sliders": '<path d="M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M20 18h0"/><circle cx="16" cy="6" r="2"/><circle cx="10" cy="12" r="2"/><circle cx="18" cy="18" r="2"/>',
    "phone": '<rect x="6" y="2.5" width="12" height="19" rx="3"/><path d="M10.5 18.5h3"/>',
    "lock": '<rect x="5" y="10" width="14" height="11" rx="2.5"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>',
    "book": '<path d="M4 4.5A2.5 2.5 0 0 1 6.5 2H20v17H6.5A2.5 2.5 0 0 0 4 21.5z"/><path d="M4 19.5V4.5"/>',
    "info": '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>',
    "box": '<path d="M3 7.5 12 3l9 4.5v9L12 21l-9-4.5z"/><path d="m3 7.5 9 4.5 9-4.5M12 12v9"/>',
}


def icon(name):
    return ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" '
            'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">'
            f'{_I[name]}</svg>')


# ---------------------------------------------------------------------------------------------
# Snippets made from the settings.
# ---------------------------------------------------------------------------------------------

def snippets(s):
    e = {k: html.escape(v) for k, v in s.items()}
    email = s["CONTACT_EMAIL"]
    out = dict(e)
    out["EMAIL_LINK"] = (f'<a href="mailto:{e["CONTACT_EMAIL"]}">{e["CONTACT_EMAIL"]}</a>' if email
                         else "<em>(email address coming soon)</em>")
    if s["PLAY_URL"]:
        out["PLAY_BUTTON"] = (f'<a class="btn" href="{e["PLAY_URL"]}" rel="noopener">{icon("play")} '
                              'Get it on Google Play</a>')
        out["PLAY_STATE"] = "Available on Google Play."
    else:
        out["PLAY_BUTTON"] = (f'<a class="btn" href="{{{{root}}}}#beta">{icon("phone")} Join the beta</a>')
        out["PLAY_STATE"] = "Not in Google Play yet: join the beta and we’ll send you the test link."
    if s["INSTALLER_URL"]:
        out["INSTALLER_BUTTON"] = (f'<a class="btn" href="{e["INSTALLER_URL"]}">{icon("download")} '
                                   'Download OwnMediaSetup.exe</a>')
    else:
        out["INSTALLER_BUTTON"] = (f'<a class="btn" aria-disabled="true" role="link">{icon("download")} '
                                   'Download link coming soon</a>')
    out["YEAR"] = str(date.today().year)
    return out


# ---------------------------------------------------------------------------------------------
# The page around the content.
# ---------------------------------------------------------------------------------------------

NAV = [
    ("download/", "Download"),
    ("guides/", "Guides"),
    ("privacy/", "Privacy"),
    ("support/", "Support"),
]

CSP = ("default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; "
       "connect-src 'self' https://formspree.io; form-action 'self' https://formspree.io; "
       "base-uri 'self'; object-src 'none'")


def header(root, path):
    def item(href, label):
        current = ' aria-current="page"' if path.startswith(href) else ""
        return f'<a href="{root}{href}"{current}>{label}</a>'

    links = "\n      ".join(item(h, l) for h, l in NAV)
    return f"""<a class="skip" href="#main">Skip to content</a>
<header class="site-header">
  <div class="wrap">
    <a class="brand" href="{root}" aria-label="OwnMedia home">
      <img src="{root}img/logo-64.webp" width="34" height="34" alt="">OwnMedia
    </a>
    <nav class="nav" aria-label="Main">
      {links}
      <a class="btn btn-small" href="{root}#beta">Get the app</a>
    </nav>
    <details class="menu">
      <summary aria-label="Menu">{icon("menu")}</summary>
      <nav class="menu-panel" aria-label="Main">
        <a href="{root}">Home</a>
        {links}
        <a class="btn" href="{root}#beta">Get the app</a>
      </nav>
    </details>
  </div>
</header>"""


def footer(root, sn):
    return f"""<footer class="site-footer">
  <div class="wrap">
    <div class="footer-grid">
      <div class="footer-brand">
        <a class="brand" href="{root}"><img src="{root}img/logo-64.webp" width="34" height="34" alt="" loading="lazy">OwnMedia</a>
        <p>Movies, shows, music and photos from your own server, on your Android phone.</p>
      </div>
      <div>
        <h2>App</h2>
        <ul>
          <li><a href="{root}#features">Features</a></li>
          <li><a href="{root}download/">Download</a></li>
          <li><a href="{root}#screens">Screenshots</a></li>
          <li><a href="{root}#faq">FAQ</a></li>
        </ul>
      </div>
      <div>
        <h2>Help</h2>
        <ul>
          <li><a href="{root}guides/windows/">Windows server</a></li>
          <li><a href="{root}guides/synology/">Synology NAS</a></li>
          <li><a href="{root}guides/docker/">Docker</a></li>
          <li><a href="{root}guides/remote-access/">Remote access &amp; friends</a></li>
          <li><a href="{root}guides/tv/">Watch on TV</a></li>
          <li><a href="{root}support/">Support</a></li>
        </ul>
      </div>
      <div>
        <h2>Company</h2>
        <address>
          {sn["COMPANY_NAME"]}<br>
          Reg. No. {sn["COMPANY_REG"]}<br>
          {sn["COMPANY_ADDRESS"]}<br>
          {sn["EMAIL_LINK"]}
        </address>
        <ul>
          <li><a href="{root}legal/">Company details</a></li>
          <li><a href="{root}privacy/">Privacy policy</a></li>
        </ul>
      </div>
    </div>
    <div class="footer-bottom">
      <span>&copy; {sn["YEAR"]} {sn["COMPANY_NAME"]}. No cookies, no analytics, no tracking.</span>
      <span>OwnMedia is an independent project, not affiliated with Jellyfin, Navidrome, Plex or Tailscale.</span>
    </div>
  </div>
</footer>"""


def page(meta, body, sn, asset_v):
    path = meta["path"]
    if meta.get("absolute"):
        root = "/"  # the 404 page is shown at any address: its links start at the site's root
    else:
        root = "../" * path.count("/") or "./"
    url = sn["SITE_URL"] + "/" + path
    title = meta["title"] if path == "" else f'{meta["title"]} — OwnMedia'
    title_e, desc_e = html.escape(title), html.escape(meta["description"])
    robots = '\n<meta name="robots" content="noindex">' if meta.get("noindex") else ""
    head = f"""<!doctype html>
<html lang="{meta.get("lang", "en")}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="{CSP}">
<title>{title_e}</title>
<meta name="description" content="{desc_e}">{robots}
<link rel="canonical" href="{url}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="OwnMedia">
<meta property="og:title" content="{title_e}">
<meta property="og:description" content="{desc_e}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{sn["SITE_URL"]}/img/og-image.jpg">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="OwnMedia: movies, music and photos from your own server">
<meta name="twitter:card" content="summary_large_image">
<meta name="theme-color" content="#eef1f6" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#080a0f" media="(prefers-color-scheme: dark)">
<link rel="icon" href="{root}favicon.ico" sizes="any">
<link rel="icon" href="{root}img/favicon-32.png" type="image/png" sizes="32x32">
<link rel="apple-touch-icon" href="{root}img/apple-touch-icon.png">
<link rel="stylesheet" href="{root}css/site.css?v={asset_v}">
<script src="{root}js/site.js?v={asset_v}" defer></script>
</head>
<body>
"""
    text = (head + header(root, path) + '\n<main id="main">\n' + body.strip() + "\n</main>\n"
            + footer(root, sn) + "\n</body>\n</html>\n")
    return fill(text, sn, root)


def fill(text, sn, root):
    text = re.sub(r"\{\{icon:([a-z-]+)\}\}", lambda m: icon(m.group(1)), text)
    for _ in range(2):  # snippets may hold {{root}}
        text = text.replace("{{root}}", root)
        text = re.sub(r"\{\{([A-Z_]+)\}\}", lambda m: sn[m.group(1)], text)
    left = re.findall(r"\{\{[^}]*\}\}", text)
    if left:
        raise SystemExit(f"Unknown placeholders: {sorted(set(left))}")
    return text


def read_page(file):
    raw = file.read_text(encoding="utf-8")
    top, body = raw.split("\n---\n", 1)
    meta = {}
    for line in top.strip().splitlines():
        key, value = line.split(":", 1)
        meta[key.strip()] = value.strip()
    meta.setdefault("path", "")
    for flag in ("noindex", "absolute", "nositemap"):
        meta[flag] = meta.get(flag) == "yes"
    return meta, body


def write(rel, text):
    target = OUT / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8", newline="\n")


def main():
    s = SETTINGS
    sn = snippets(s)
    if OUT.exists():
        shutil.rmtree(OUT)
    shutil.copytree(STATIC, OUT)

    digest = hashlib.sha1()
    for f in sorted((STATIC / "css").glob("*")) + sorted((STATIC / "js").glob("*")):
        digest.update(f.read_bytes())
    asset_v = digest.hexdigest()[:8]

    sitemap = []
    for file in sorted(PAGES.rglob("*.html")):
        meta, body = read_page(file)
        path = meta["path"]
        out_file = meta.get("file") or (path + "index.html")
        write(out_file, page(meta, body, sn, asset_v))
        if not (meta["noindex"] or meta["nositemap"]):
            sitemap.append(path)

    # The old address of the privacy policy (it may be in Google Play already) keeps working:
    # .htaccess sends it on with a permanent redirect, and this file does the same where
    # .htaccess is not read.
    new = s["SITE_URL"] + "/privacy/"
    write("privacy.html", f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>OwnMedia privacy policy</title>
<meta name="robots" content="noindex">
<link rel="canonical" href="{new}">
<meta http-equiv="refresh" content="0; url=privacy/">
</head>
<body>
<p>The privacy policy has moved: <a href="privacy/">OwnMedia privacy policy</a>.</p>
</body>
</html>
""")

    today = date.today().isoformat()
    urls = "\n".join(f"  <url><loc>{s['SITE_URL']}/{p}</loc><lastmod>{today}</lastmod></url>" for p in sitemap)
    write("sitemap.xml", f'<?xml version="1.0" encoding="UTF-8"?>\n'
                         f'<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n{urls}\n</urlset>\n')
    write("robots.txt", f"User-agent: *\nAllow: /\n\nSitemap: {s['SITE_URL']}/sitemap.xml\n")

    # The same as an archive for Hostinger's File Manager (upload, then Extract into public_html).
    # The README is for the owner, not for visitors.
    archive = SRC.parent / "ownmedia-site.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(OUT.rglob("*")):
            if f.is_file() and f.name != "README.md":
                z.write(f, f.relative_to(OUT).as_posix())

    print(f"Built {len(sitemap)} pages (+404, privacy.html) into {OUT}, and {archive.name}")
    missing = [k for k in ("CONTACT_EMAIL", "PLAY_URL", "INSTALLER_URL") if not s[k]]
    if missing:
        print("Not given yet (placeholders on the site): " + ", ".join(missing), file=sys.stderr)


if __name__ == "__main__":
    main()
