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

Other languages: the same pages in site-src/pages/<lang>/ (de, fr, es) with the same "path:" as the
English page; they are built under de/, fr/, es/. Links to {{root}}<path> inside such a page go to the
page in the same language when it is translated, and to the English one when it isn't (privacy,
company details). The words of the header, footer and buttons are in strings.py.
No third-party code: Python's standard library only.
"""

import hashlib
import html
import os
import json
import re
import shutil
import sys
import zipfile
from datetime import date
from pathlib import Path

from strings import LANGS, NBSP, OG_LOCALE, UI

# ---------------------------------------------------------------------------------------------
# SETTINGS: the owner's answers. Empty means "not given yet": the site shows a placeholder and
# the build prints a reminder.
# ---------------------------------------------------------------------------------------------

SETTINGS = {
    # The site's full address, without a slash at the end. Used only where a full address is a
    # must: sitemap.xml, robots.txt, link previews (Open Graph) and the canonical address.
    "SITE_URL": "https://ownmedia.app",
    # Email for privacy questions and support.
    "CONTACT_EMAIL": "support@ownmedia.app",
    # The company, letter for letter as in the Google payments profile and D-U-N-S.
    "COMPANY_NAME": "MROYA SIA",
    "COMPANY_REG": "50203370261",
    # As the owner gave it (17.10.2026), letter for letter.
    "COMPANY_ADDRESS": "Riga, Ganibu dambis 20A, LV-1045",
    "COMPANY_COUNTRY": "Latvia",
    # The app in Google Play; empty while it is not published (the site offers the beta instead).
    "PLAY_URL": "",
    # Where OwnMediaSetup.exe is downloaded from; empty while there is no public link. {{root}} makes
    # it a link to the file on this site (copied there from INSTALLER_FILE by the build).
    "INSTALLER_URL": "{{root}}download/OwnMediaSetup.exe",
    # The release the site serves: the build copies it to site/download/OwnMediaSetup.exe. The file is
    # too big for git: it stays in the release folder (git ignores the copy in site/).
    "INSTALLER_FILE": r"D:\APP\OwnMedia-release\0.3.13\OwnMediaSetup.exe",
    "INSTALLER_VERSION": "0.3.13",
    # The Android app file the site serves at a fixed address, download/OwnMedia.apk. publish-app.cmd
    # leaves the fresh signed build in app\dist\site\OwnMedia.apk; the build copies it from there
    # (too big for git, like the installer). The version shown next to it comes from version.json,
    # which publish-app.cmd writes beside the file (and the app reads to offer updates).
    "APK_URL": "{{root}}download/OwnMedia.apk",
    "APK_FILE": r"D:\APP\OwnMedia\app\dist\site\OwnMedia.apk",
    # The Jellyfin plugin catalogue for NAS, Docker and Linux (jellyfin-repo/manifest.json).
    "CATALOG_URL": "https://raw.githubusercontent.com/3dengineering01-star/Homeplayer/main/jellyfin-repo/manifest.json",
    # Bing Webmaster Tools: proof that the site is ours (meta msvalidate.01 on the English home page).
    # Keep it: without it Bing drops the site from Webmaster Tools.
    "BING_SITE_VERIFY": "57ECC0031F97FE2A0B4B5B47E935AB6C",
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
    "signal": '<path d="M4 20v-3M9 20v-7M14 20V9M19 20V4"/>',
    "spark": '<path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M6 18l2.5-2.5M15.5 8.5 18 6"/>',
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

def email_link(email):
    """The contact address, hidden from address-harvesting bots: the page holds it reversed in two
    parts, and site.js puts it together into a normal mailto link. Without the script it reads
    "support (at) ownmedia.app", which people understand and simple harvesters don't pick up."""
    user, domain = email.split("@", 1)
    return (f'<a class="mail-link" data-u="{html.escape(user[::-1])}" data-d="{html.escape(domain[::-1])}">'
            f'{html.escape(user)} (at) {html.escape(domain)}</a>')


def snippets(s, lang="en"):
    u = UI[lang]
    e = {k: html.escape(v) for k, v in s.items()}
    email = s["CONTACT_EMAIL"]
    out = dict(e)
    out["EMAIL_LINK"] = email_link(email) if email else f"<em>{u['email_soon']}</em>"
    if s["PLAY_URL"]:
        out["PLAY_BUTTON"] = (f'<a class="btn" href="{e["PLAY_URL"]}" rel="noopener">{icon("play")} '
                              f'{u["play_button"]}</a>')
        out["PLAY_STATE"] = u["play_state"]
    else:
        out["PLAY_BUTTON"] = f'<a class="btn" href="{{{{root}}}}#play">{icon("phone")} {u["notify_button"]}</a>'
        out["PLAY_STATE"] = u["play_soon"]
    if s["INSTALLER_URL"]:
        out["INSTALLER_BUTTON"] = (f'<a class="btn" href="{e["INSTALLER_URL"]}" download>{icon("download")} '
                                   f'{u["installer_button"]}</a>')
    else:
        out["INSTALLER_BUTTON"] = (f'<a class="btn" aria-disabled="true" role="link">{icon("download")} '
                                   f'{u["installer_soon"]}</a>')
    out["INSTALLER_META"] = installer_meta(s, u)
    apk = Path(s["APK_FILE"])
    if s["APK_URL"] and apk.is_file():
        v = html.escape(apk_version(apk))
        out["APP_VERSION"] = v
        out["APK_BUTTON"] = (f'<a class="btn" href="{e["APK_URL"]}" download type="application/vnd.android.package-archive">'
                             f'{icon("download")} {u["apk_button"]}</a>')
        mb = round(apk.stat().st_size / 1_000_000)
        sha = hashlib.sha256(apk.read_bytes()).hexdigest()
        warn = u["apk_warn"]
        out["APK_NOTE"] = f'<p class="hero-note">{u["apk_note"].format(v=v, warn=warn)}</p>'
        out["APK_META"] = (f'<p class="dl-note">{u["apk_meta"].format(v=v, mb=mb, warn=warn)}</p>'
                           f'<p class="dl-meta">SHA-256: <code class="sha">{sha}</code></p>')
        out["ANDROID_STATE"] = u["android_state"]
    else:
        out["APP_VERSION"] = ""
        out["APK_BUTTON"] = out["PLAY_BUTTON"]
        out["APK_NOTE"] = ""
        out["APK_META"] = ""
        out["ANDROID_STATE"] = out["PLAY_STATE"]
    out["YEAR"] = str(date.today().year)
    return out


def apk_version(apk):
    """The app's version from version.json next to the file ("0.3.15"), as publish-app.cmd wrote it."""
    info = apk.with_name("version.json")
    try:
        return str(json.loads(info.read_text(encoding="utf-8-sig"))["version"])
    except (OSError, ValueError, KeyError) as err:
        raise SystemExit(f"No version for the app: {info} ({err})")


def installer_meta(s, u):
    """Version, size and checksum of the installer, and what to do about Windows' warning."""
    f = Path(s["INSTALLER_FILE"])
    if not (s["INSTALLER_URL"] and f.is_file()):
        return ""
    sha = hashlib.sha256(f.read_bytes()).hexdigest()
    mb = round(f.stat().st_size / 1_000_000)
    return (f'<p class="dl-meta">{u["version"]} {html.escape(s["INSTALLER_VERSION"])}, {mb} {u["mb"]}. '
            f'SHA-256: <code class="sha">{sha}</code></p>'
            f'<p class="dl-note">{u["installer_unsigned"]}</p>')


# ---------------------------------------------------------------------------------------------
# The page around the content.
# ---------------------------------------------------------------------------------------------

NAV = ["download/", "guides/", "privacy/", "support/"]

CSP = ("default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; "
       "connect-src 'self' https://formspree.io; form-action 'self' https://formspree.io; "
       "base-uri 'self'; object-src 'none'")


def prefix(lang):
    """Where a language's pages live: "" for English, "de/" for German."""
    return "" if lang == "en" else f"{lang}/"


def lang_links(lang, key, keys, cls):
    """Links to this page in each language (to that language's home where it isn't translated).
    {{top}} is the site's root like {{root}}, but these links are never moved into the page's language."""
    items = []
    for code, name in LANGS.items():
        target = prefix(code) + (key if key in keys[code] else "")
        current = ' aria-current="true"' if code == lang else ""
        items.append(f'<a href="{{{{top}}}}{target}" hreflang="{code}" lang="{code}"{current}>{name}</a>')
    return f'<div class="{cls}">' + "".join(items) + "</div>"


def header(key, lang, keys):
    u = UI[lang]

    def item(href):
        current = ' aria-current="page"' if key.startswith(href) else ""
        return f'<a href="{{{{root}}}}{href}"{current}>{u["nav"][href]}</a>'

    links = "\n      ".join(item(h) for h in NAV)
    return f"""<a class="skip" href="#main">{u["skip"]}</a>
<header class="site-header">
  <div class="wrap">
    <a class="brand" href="{{{{root}}}}" aria-label="{u["home_aria"]}">
      <img src="{{{{root}}}}img/logo-64.webp" width="34" height="34" alt="">OwnMedia
    </a>
    <nav class="nav" aria-label="Main">
      {links}
      <details class="lang">
        <summary aria-label="{u["language"]}: {LANGS[lang]}">{icon("globe")}<span>{lang.upper()}</span></summary>
        {lang_links(lang, key, keys, "lang-panel")}
      </details>
      <a class="btn btn-small" href="{{{{root}}}}download/#android">{u["get_app"]}</a>
    </nav>
    <details class="menu">
      <summary class="tip-below" aria-label="{u["open_menu"]}" data-tip="{u["open_menu"]}">{icon("menu")}</summary>
      <nav class="menu-panel" aria-label="Main">
        <a href="{{{{root}}}}">{u["home"]}</a>
        {links}
        <a class="btn" href="{{{{root}}}}download/#android">{u["get_app"]}</a>
        {lang_links(lang, key, keys, "menu-langs")}
      </nav>
    </details>
  </div>
</header>"""


def footer(sn, lang, key, keys):
    # Only the company name and the email here: the registration number and the address are on
    # legal/ and in the privacy policy, one click away, as the e-commerce rules ask.
    u = UI[lang]
    return f"""<footer class="site-footer">
  <div class="wrap">
    <div class="footer-grid">
      <div class="footer-brand">
        <a class="brand" href="{{{{root}}}}"><img src="{{{{root}}}}img/logo-64.webp" width="34" height="34" alt="" loading="lazy">OwnMedia</a>
        <p>{u["tagline"]}</p>
      </div>
      <div>
        <h2>{u["f_app"]}</h2>
        <ul>
          <li><a href="{{{{root}}}}#features">{u["f_features"]}</a></li>
          <li><a href="{{{{root}}}}#whats-new">{u["f_whatsnew"]}</a></li>
          <li><a href="{{{{root}}}}#share">{u["f_sharing"]}</a></li>
          <li><a href="{{{{root}}}}download/">{u["f_download"]}</a></li>
          <li><a href="{{{{root}}}}#screens">{u["f_screens"]}</a></li>
          <li><a href="{{{{root}}}}#faq">{u["f_faq"]}</a></li>
        </ul>
      </div>
      <div>
        <h2>{u["f_help"]}</h2>
        <ul>
          <li><a href="{{{{root}}}}guides/windows/">{u["f_windows"]}</a></li>
          <li><a href="{{{{root}}}}guides/synology/">{u["f_synology"]}</a></li>
          <li><a href="{{{{root}}}}guides/docker/">{u["f_docker"]}</a></li>
          <li><a href="{{{{root}}}}guides/remote-access/">{u["f_remote"]}</a></li>
          <li><a href="{{{{root}}}}guides/tv/">{u["f_tv"]}</a></li>
          <li><a href="{{{{root}}}}support/">{u["f_support"]}</a></li>
        </ul>
      </div>
      <div>
        <h2>{u["f_company"]}</h2>
        <address>
          {sn["COMPANY_NAME"]}<br>
          {sn["EMAIL_LINK"]}
        </address>
        <ul>
          <li><a href="{{{{root}}}}legal/">{u["company_details"]}</a></li>
          <li><a href="{{{{root}}}}privacy/">{u["privacy_policy"]}</a></li>
        </ul>
      </div>
    </div>
    <div class="footer-bottom">
      <span>&copy; {sn["YEAR"]} {sn["COMPANY_NAME"]}. {u["no_cookies"]}</span>
      <span>{u["independent"]}</span>
    </div>
    <nav class="footer-langs" aria-label="{u["language"]}">{lang_links(lang, key, keys, "footer-langs-list")}</nav>
  </div>
</footer>"""


def page(meta, body, sn, asset_v, keys):
    key, lang = meta["path"], meta["lang"]
    path = prefix(lang) + key
    if meta.get("absolute"):
        root = "/"  # the 404 page is shown at any address: its links start at the site's root
    else:
        root = "../" * path.count("/") or "./"
    url = sn["SITE_URL"] + "/" + path
    title = meta["title"] if key == "" else f'{meta["title"]} — OwnMedia'
    title_e, desc_e = html.escape(title), html.escape(meta["description"])
    robots = '\n<meta name="robots" content="noindex">' if meta.get("noindex") else ""
    if key == "" and lang == "en" and sn.get("BING_SITE_VERIFY"):
        robots += f'\n<meta name="msvalidate.01" content="{sn["BING_SITE_VERIFY"]}">'
    # The same page in the other languages, for search engines; English is the default.
    langs = [code for code in LANGS if key in keys[code]]
    alternates = ""
    if len(langs) > 1 and not meta.get("noindex"):
        alternates = "".join(f'\n<link rel="alternate" hreflang="{code}" href="{sn["SITE_URL"]}/{prefix(code)}{key}">'
                             for code in langs)
        alternates += f'\n<link rel="alternate" hreflang="x-default" href="{sn["SITE_URL"]}/{key}">'
        if lang == "en":
            # Opens the page in the browser's language, before anything is drawn (js/lang.js).
            alternates += f'\n<script src="{root}js/lang.js?v={asset_v}"></script>'
    head = f"""<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="{CSP}">
<title>{title_e}</title>
<meta name="description" content="{desc_e}">{robots}
<link rel="canonical" href="{url}">{alternates}
<meta property="og:type" content="website">
<meta property="og:site_name" content="OwnMedia">
<meta property="og:locale" content="{OG_LOCALE[lang]}">
<meta property="og:title" content="{title_e}">
<meta property="og:description" content="{desc_e}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{sn["SITE_URL"]}/img/og-image.jpg">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="{UI[lang]["og_alt"]}">
<meta name="twitter:card" content="summary_large_image">
<meta name="theme-color" content="#eef1f6" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#080a0f" media="(prefers-color-scheme: dark)">
<link rel="icon" href="{root}favicon.ico" sizes="any">
<link rel="icon" href="{root}img/favicon-32.png" type="image/png" sizes="32x32">
<link rel="apple-touch-icon" href="{root}img/apple-touch-icon.png">
<link rel="preload" href="{root}fonts/bricolage-grotesque-600.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="{root}css/site.css?v={asset_v}">
<script src="{root}js/site.js?v={asset_v}" defer></script>
</head>
<body>
"""
    text = (head + header(key, lang, keys) + '\n<main id="main">\n' + body.strip() + "\n</main>\n"
            + footer(sn, lang, key, keys) + "\n</body>\n</html>\n")
    return fill(text, sn, root, lang, keys)


# A screenshot that may not be taken yet: {{shot:name|alt text|caption|small caption}} shows
# img/screens/<name>.webp in a phone frame. Until that file exists, the preview build
# (OWNMEDIA_PREVIEW=1) shows a dashed placeholder saying which shot to take, and the real build
# leaves it out.
PREVIEW = os.environ.get("OWNMEDIA_PREVIEW") == "1"


def shot(m):
    name, alt, cap, sub = m.group(1), m.group(2), m.group(3), m.group(4)
    if (STATIC / "img" / "screens" / f"{name}.webp").is_file():
        return (f'<figure class="shot"><div class="phone"><img src="{{{{root}}}}img/screens/{name}.webp" '
                f'width="600" height="1300" alt="{alt}" loading="lazy"></div>'
                f'<figcaption>{cap}<span>{sub}</span></figcaption></figure>')
    if PREVIEW:
        return (f'<figure class="shot shot-todo"><div class="phone"><div class="todo">Screenshot to take:<br>'
                f'<b>{alt}</b><br><code>img/screens/{name}.webp</code></div></div>'
                f'<figcaption>{cap}<span>{sub}</span></figcaption></figure>')
    return ""


def localize(text, lang, keys):
    """Links to pages of the site go to the page in the same language, when it has one."""
    if lang == "en":
        return text

    def move(m):
        target = m.group(2)
        return f"{m.group(1)}{{{{root}}}}{prefix(lang)}{target}" if target in keys[lang] else m.group(0)

    return re.sub(r'(href=")\{\{root\}\}([^"#?]*)', move, text)


def french_spaces(body):
    """French puts a no-break space before : ; ? ! and inside « »; not in code, tags or placeholders."""
    out, skip = [], 0
    for part in re.split(r"(<[^>]+>|\{\{[^}]*\}\})", body):
        if part.startswith("<"):
            tag = re.match(r"</?(\w+)", part)
            if tag and tag.group(1).lower() in ("pre", "code"):
                skip += -1 if part.startswith("</") else 1
        elif not part.startswith("{{") and not skip:
            part = re.sub(r" ([:;?!»])", NBSP + r"\1", part).replace("« ", "«" + NBSP)
        out.append(part)
    return "".join(out)


def fill(text, sn, root, lang="en", keys=None):
    text = re.sub(r"\{\{icon:([a-z-]+)\}\}", lambda m: icon(m.group(1)), text)
    text = re.sub(r"\{\{shot:([a-z0-9-]+)\|([^|}]*)\|([^|}]*)\|([^|}]*)\}\}", shot, text)
    for _ in range(2):  # snippets may hold {{root}}
        if keys:
            text = localize(text, lang, keys)
        text = text.replace("{{root}}", root).replace("{{top}}", root)
        text = re.sub(r"\{\{([A-Z_]+)\}\}", lambda m: sn[m.group(1)], text)
    left = re.findall(r"\{\{[^}]*\}\}", text)
    if left:
        raise SystemExit(f"Unknown placeholders: {sorted(set(left))}")
    return text


def read_page(file):
    raw = file.read_text(encoding="utf-8")
    top, body = raw.split("\n---\n", 1)
    lang = file.parent.name if file.parent != PAGES else "en"
    if lang == "fr":
        body = french_spaces(body)
    meta = {"lang": lang}
    for line in top.strip().splitlines():
        key, value = line.split(":", 1)
        meta[key.strip()] = value.strip()
    meta.setdefault("path", "")
    for flag in ("noindex", "absolute", "nositemap"):
        meta[flag] = meta.get(flag) == "yes"
    return meta, body


# Pictures get ?v=<their checksum> in every page, like the CSS and the script: a picture that
# changes under the same name (a new screenshot) then reaches browsers that cached the old one.
IMG_VERSIONS = {}


def version_images(text):
    def add(m):
        rel = m.group(2)
        v = IMG_VERSIONS.get(rel)
        return f'{m.group(1)}{rel}?v={v}"' if v else m.group(0)
    return re.sub(r'((?:src|href|content)="[^"]*?)(img/[^"?]+)"', add, text)


def write(rel, text):
    target = OUT / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8", newline="\n")


def main():
    s = SETTINGS
    # Empty site/ and fill it again. The folder itself stays: it may be open in Explorer or a shell.
    OUT.mkdir(exist_ok=True)
    for old in OUT.iterdir():
        shutil.rmtree(old) if old.is_dir() else old.unlink()
    shutil.copytree(STATIC, OUT, dirs_exist_ok=True)
    installer = Path(s["INSTALLER_FILE"])
    if s["INSTALLER_URL"] and installer.is_file():
        (OUT / "download").mkdir(exist_ok=True)
        shutil.copy2(installer, OUT / "download" / "OwnMediaSetup.exe")
    elif s["INSTALLER_URL"]:
        print(f"Installer not found: {installer}", file=sys.stderr)
    apk = Path(s["APK_FILE"])
    if s["APK_URL"] and apk.is_file():
        (OUT / "download").mkdir(exist_ok=True)
        shutil.copy2(apk, OUT / "download" / "OwnMedia.apk")
        shutil.copy2(apk.with_name("version.json"), OUT / "download" / "version.json")
    elif s["APK_URL"]:
        print(f"Android app not found: {apk}", file=sys.stderr)

    digest = hashlib.sha1()
    for f in sorted((STATIC / "css").glob("*")) + sorted((STATIC / "js").glob("*")):
        digest.update(f.read_bytes())
    asset_v = digest.hexdigest()[:8]

    for f in (OUT / "img").rglob("*"):
        if f.is_file():
            IMG_VERSIONS[f.relative_to(OUT).as_posix()] = hashlib.sha1(f.read_bytes()).hexdigest()[:8]

    pages = []
    for lang in LANGS:
        folder = PAGES if lang == "en" else PAGES / lang
        pages += [read_page(f) for f in sorted(folder.glob("*.html"))]
    unknown = {f.parent.name for f in PAGES.glob("*/*.html")} - set(LANGS)
    if unknown:
        raise SystemExit(f"Pages in a language strings.py doesn't know: {sorted(unknown)}")
    # Which pages each language has, by their path: links and the language switcher use it.
    keys = {lang: {m["path"] for m, _ in pages if m["lang"] == lang} for lang in LANGS}
    snips = {lang: snippets(s, lang) for lang in LANGS}

    sitemap = []
    for meta, body in pages:
        path = prefix(meta["lang"]) + meta["path"]
        out_file = meta.get("file") or (path + "index.html")
        write(out_file, version_images(page(meta, body, snips[meta["lang"]], asset_v, keys)))
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
