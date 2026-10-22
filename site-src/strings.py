"""The words around the pages (header, footer, buttons, notes about the files) in each language of
the site. The pages themselves are in site-src/pages/ (English) and site-src/pages/<lang>/.

English is the main language: its pages are at the site's root, the others under de/, fr/, es/.
A page that has no translation (the privacy policy, the company details) is linked in English.
German speaks to the reader as "du", French as "vous", Spanish as "tú".
"""

# The order is the order of the language switcher.
LANGS = {"en": "English", "de": "Deutsch", "fr": "Français", "es": "Español"}
OG_LOCALE = {"en": "en_US", "de": "de_DE", "fr": "fr_FR", "es": "es_ES"}

NBSP = " "

UI = {
    "en": {
        "skip": "Skip to content",
        "home_aria": "OwnMedia home",
        "open_menu": "Open menu",
        "home": "Home",
        "nav": {"download/": "Download", "guides/": "Guides", "privacy/": "Privacy", "support/": "Support"},
        "get_app": "Get the app",
        "language": "Language",
        "tagline": "Movies, shows, music and photos from your own server, on your Android phone.",
        "f_app": "App",
        "f_features": "Features",
        "f_whatsnew": "What’s new",
        "f_sharing": "Sharing with friends",
        "f_download": "Download",
        "f_screens": "Screenshots",
        "f_faq": "FAQ",
        "f_help": "Help",
        "f_windows": "Windows server",
        "f_synology": "Synology NAS",
        "f_docker": "Docker",
        "f_remote": "Remote access &amp; friends",
        "f_tv": "Watch on TV",
        "f_support": "Support",
        "f_company": "Company",
        "reg_no": "Reg. No.",
        "company_details": "Company details",
        "privacy_policy": "Privacy policy",
        "no_cookies": "No cookies, no analytics, no tracking.",
        "independent": "OwnMedia is an independent project, not affiliated with Jellyfin, Navidrome, Plex or Tailscale.",
        "email_soon": "(email address coming soon)",
        "play_button": "Get it on Google Play",
        "play_state": "Available on Google Play.",
        "notify_button": "Get notified",
        "play_soon": "Coming to Google Play: leave your email and we’ll write when it’s there.",
        "installer_button": "Download OwnMediaSetup.exe",
        "installer_soon": "Download link coming soon",
        "version": "Version",
        "mb": "MB",
        "installer_unsigned": ("The installer isn’t digitally signed yet, so Windows may say "
                               "<i>“Windows protected your PC”</i>. Click <i>More info</i>, then <i>Run anyway</i>."),
        "apk_button": "Download for Android",
        "apk_warn": ("If the phone warns about an unknown developer, tap <i>More details</i> → "
                     "<i>Install anyway</i>."),
        "apk_note": ("Version {v} for Android phones. {warn} The app tells you when a new version is out."
                     "<small>Coming to Google Play.</small>"),
        "apk_meta": ("Version {v} for Android phones, {mb} MB. {warn} If it asks, allow installing apps from "
                     "your browser. The app tells you when a new version is out; it installs over the old one, "
                     "and your servers and settings stay."),
        "android_state": "The app for your phone: movies, shows, music and photos from your servers.",
        "og_alt": "OwnMedia: movies, music and photos from your own server",
    },
    "de": {
        "skip": "Zum Inhalt springen",
        "home_aria": "OwnMedia Startseite",
        "open_menu": "Menü öffnen",
        "home": "Startseite",
        "nav": {"download/": "Download", "guides/": "Anleitungen", "privacy/": "Datenschutz", "support/": "Support"},
        "get_app": "App holen",
        "language": "Sprache",
        "tagline": "Filme, Serien, Musik und Fotos von deinem eigenen Server, auf deinem Android-Handy.",
        "f_app": "App",
        "f_features": "Funktionen",
        "f_whatsnew": "Neuigkeiten",
        "f_sharing": "Mit Freunden teilen",
        "f_download": "Download",
        "f_screens": "Screenshots",
        "f_faq": "Fragen &amp; Antworten",
        "f_help": "Hilfe",
        "f_windows": "Server unter Windows",
        "f_synology": "Synology NAS",
        "f_docker": "Docker",
        "f_remote": "Unterwegs &amp; Freunde",
        "f_tv": "Auf dem Fernseher",
        "f_support": "Support",
        "f_company": "Unternehmen",
        "reg_no": "Reg.-Nr.",
        "company_details": "Firmenangaben (Englisch)",
        "privacy_policy": "Datenschutzerklärung (Englisch)",
        "no_cookies": "Keine Cookies, keine Statistik, kein Tracking.",
        "independent": ("OwnMedia ist ein unabhängiges Projekt und steht in keiner Verbindung zu Jellyfin, "
                        "Navidrome, Plex oder Tailscale."),
        "email_soon": "(E-Mail-Adresse folgt)",
        "play_button": "Bei Google Play laden",
        "play_state": "Bei Google Play erhältlich.",
        "notify_button": "Benachrichtigen",
        "play_soon": "Bald bei Google Play: Hinterlasse deine E-Mail, und wir schreiben dir, sobald es so weit ist.",
        "installer_button": "OwnMediaSetup.exe herunterladen",
        "installer_soon": "Download-Link folgt",
        "version": "Version",
        "mb": "MB",
        "installer_unsigned": ("Das Installationsprogramm ist noch nicht digital signiert, deshalb meldet Windows "
                               "vielleicht <i>„Der Computer wurde durch Windows geschützt“</i>. Klicke auf "
                               "<i>Weitere Informationen</i> und dann auf <i>Trotzdem ausführen</i>."),
        "apk_button": "Für Android herunterladen",
        "apk_warn": ("Warnt das Handy vor einem unbekannten Entwickler, tippe auf <i>Weitere Details</i> → "
                     "<i>Trotzdem installieren</i>."),
        "apk_note": ("Version {v} für Android-Handys. {warn} Die App sagt dir, wenn eine neue Version da ist."
                     "<small>Bald bei Google Play.</small>"),
        "apk_meta": ("Version {v} für Android-Handys, {mb} MB. {warn} Wenn das Handy fragt, erlaube die "
                     "Installation von Apps aus deinem Browser. Die App sagt dir, wenn eine neue Version da ist; "
                     "sie wird über die alte installiert, deine Server und Einstellungen bleiben."),
        "android_state": "Die App für dein Handy: Filme, Serien, Musik und Fotos von deinen Servern.",
        "og_alt": "OwnMedia: Filme, Musik und Fotos von deinem eigenen Server",
    },
    "fr": {
        "skip": "Aller au contenu",
        "home_aria": "Accueil OwnMedia",
        "open_menu": "Ouvrir le menu",
        "home": "Accueil",
        "nav": {"download/": "Télécharger", "guides/": "Guides", "privacy/": "Confidentialité",
                "support/": "Assistance"},
        "get_app": "Obtenir l’app",
        "language": "Langue",
        "tagline": "Films, séries, musique et photos de votre propre serveur, sur votre téléphone Android.",
        "f_app": "Application",
        "f_features": "Fonctionnalités",
        "f_whatsnew": "Nouveautés",
        "f_sharing": "Partager avec vos proches",
        "f_download": "Télécharger",
        "f_screens": "Captures d’écran",
        "f_faq": "Questions fréquentes",
        "f_help": "Aide",
        "f_windows": "Serveur sous Windows",
        "f_synology": "NAS Synology",
        "f_docker": "Docker",
        "f_remote": "Hors de chez vous et amis",
        "f_tv": "Regarder sur la télé",
        "f_support": "Assistance",
        "f_company": "Société",
        "reg_no": "N° d’immatriculation",
        "company_details": "Informations sur la société (en anglais)",
        "privacy_policy": "Politique de confidentialité (en anglais)",
        "no_cookies": "Pas de cookies, pas de statistiques, pas de pistage.",
        "independent": ("OwnMedia est un projet indépendant, sans lien avec Jellyfin, Navidrome, Plex ou "
                        "Tailscale."),
        "email_soon": "(adresse e-mail bientôt disponible)",
        "play_button": "Disponible sur Google Play",
        "play_state": "Disponible sur Google Play.",
        "notify_button": "Me prévenir",
        "play_soon": f"Bientôt sur Google Play{NBSP}: laissez votre e-mail et nous vous écrirons dès qu’elle y sera.",
        "installer_button": "Télécharger OwnMediaSetup.exe",
        "installer_soon": "Lien de téléchargement bientôt disponible",
        "version": "Version",
        "mb": "Mo",
        "installer_unsigned": (f"Le programme d’installation n’est pas encore signé numériquement{NBSP}: Windows "
                               f"peut afficher <i>«{NBSP}Windows a protégé votre ordinateur{NBSP}»</i>. Cliquez sur "
                               "<i>Informations complémentaires</i>, puis sur <i>Exécuter quand même</i>."),
        "apk_button": "Télécharger pour Android",
        "apk_warn": ("Si le téléphone signale un développeur inconnu, touchez <i>Plus de détails</i> → "
                     "<i>Installer quand même</i>."),
        "apk_note": ("Version {v} pour téléphones Android. {warn} L’app vous prévient quand une nouvelle version "
                     "sort.<small>Bientôt sur Google Play.</small>"),
        "apk_meta": ("Version {v} pour téléphones Android, {mb} Mo. {warn} Si on vous le demande, autorisez "
                     "l’installation d’applications depuis votre navigateur. L’app vous prévient quand une nouvelle "
                     f"version sort{NBSP}; elle s’installe par-dessus l’ancienne, et vos serveurs et réglages "
                     "sont conservés."),
        "android_state": f"L’app pour votre téléphone{NBSP}: films, séries, musique et photos de vos serveurs.",
        "og_alt": f"OwnMedia{NBSP}: films, musique et photos de votre propre serveur",
    },
    "es": {
        "skip": "Saltar al contenido",
        "home_aria": "Inicio de OwnMedia",
        "open_menu": "Abrir menú",
        "home": "Inicio",
        "nav": {"download/": "Descargar", "guides/": "Guías", "privacy/": "Privacidad", "support/": "Soporte"},
        "get_app": "Obtener la app",
        "language": "Idioma",
        "tagline": "Películas, series, música y fotos de tu propio servidor, en tu teléfono Android.",
        "f_app": "App",
        "f_features": "Funciones",
        "f_whatsnew": "Novedades",
        "f_sharing": "Compartir con amigos",
        "f_download": "Descargar",
        "f_screens": "Capturas de pantalla",
        "f_faq": "Preguntas frecuentes",
        "f_help": "Ayuda",
        "f_windows": "Servidor en Windows",
        "f_synology": "NAS Synology",
        "f_docker": "Docker",
        "f_remote": "Fuera de casa y amigos",
        "f_tv": "Ver en la tele",
        "f_support": "Soporte",
        "f_company": "Empresa",
        "reg_no": "N.º de registro",
        "company_details": "Datos de la empresa (en inglés)",
        "privacy_policy": "Política de privacidad (en inglés)",
        "no_cookies": "Sin cookies, sin analítica, sin rastreo.",
        "independent": ("OwnMedia es un proyecto independiente, sin relación con Jellyfin, Navidrome, Plex ni "
                        "Tailscale."),
        "email_soon": "(dirección de correo próximamente)",
        "play_button": "Disponible en Google Play",
        "play_state": "Disponible en Google Play.",
        "notify_button": "Avísame",
        "play_soon": "Pronto en Google Play: déjanos tu correo y te escribiremos cuando esté.",
        "installer_button": "Descargar OwnMediaSetup.exe",
        "installer_soon": "Enlace de descarga próximamente",
        "version": "Versión",
        "mb": "MB",
        "installer_unsigned": ("El instalador aún no tiene firma digital, así que Windows puede mostrar "
                               "<i>«Windows protegió su PC»</i>. Haz clic en <i>Más información</i> y luego en "
                               "<i>Ejecutar de todas formas</i>."),
        "apk_button": "Descargar para Android",
        "apk_warn": ("Si el teléfono avisa de un desarrollador desconocido, toca <i>Más detalles</i> → "
                     "<i>Instalar de todas formas</i>."),
        "apk_note": ("Versión {v} para teléfonos Android. {warn} La app te avisa cuando sale una versión nueva."
                     "<small>Pronto en Google Play.</small>"),
        "apk_meta": ("Versión {v} para teléfonos Android, {mb} MB. {warn} Si te lo pide, permite instalar apps "
                     "desde tu navegador. La app te avisa cuando sale una versión nueva; se instala encima de la "
                     "anterior y tus servidores y ajustes se conservan."),
        "android_state": "La app para tu teléfono: películas, series, música y fotos de tus servidores.",
        "og_alt": "OwnMedia: películas, música y fotos de tu propio servidor",
    },
}
