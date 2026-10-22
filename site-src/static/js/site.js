// OwnMedia site: the Google Play sign-up form, the screenshot buttons, the copy buttons and the remembered
// language. Nothing else: no tracking, no cookies, nothing loaded from other sites. Each part runs only where its
// element is on the page.

(function () {
  "use strict";

  // Messages in the page's language (<html lang>); English when it isn't one of these.
  var TEXT = {
    en: { email: "Enter an email like name@example.com.", sending: "Sending…",
      thanks: "Thanks! We'll write once OwnMedia is on Google Play.",
      failed: "The sign-up didn’t reach us. Check your connection, then select Notify me again.", copied: "Copied" },
    de: { email: "Gib eine E-Mail-Adresse wie name@example.com ein.", sending: "Wird gesendet…",
      thanks: "Danke! Wir schreiben dir, sobald OwnMedia bei Google Play ist.",
      failed: "Die Anmeldung ist nicht bei uns angekommen. Prüfe deine Verbindung und wähle dann noch einmal „Benachrichtigen“.",
      copied: "Kopiert" },
    fr: { email: "Saisissez une adresse comme nom@exemple.com.", sending: "Envoi…",
      thanks: "Merci ! Nous vous écrirons dès qu’OwnMedia sera sur Google Play.",
      failed: "L’inscription ne nous est pas parvenue. Vérifiez votre connexion, puis sélectionnez à nouveau « Me prévenir ».",
      copied: "Copié" },
    es: { email: "Escribe un correo como nombre@ejemplo.com.", sending: "Enviando…",
      thanks: "¡Gracias! Te escribiremos cuando OwnMedia esté en Google Play.",
      failed: "La inscripción no nos llegó. Revisa tu conexión y vuelve a pulsar «Avísame».", copied: "Copiado" }
  };
  var T = TEXT[document.documentElement.lang] || TEXT.en;

  // Beta sign-up: the same Formspree form as the old waitlist page.
  var FORM_ENDPOINT = "https://formspree.io/f/mqpawabz";
  var form = document.getElementById("beta-form");
  if (form) {
    var status = document.getElementById("form-status");
    var button = form.querySelector("button[type=submit]");
    var show = function (text, kind) {
      status.textContent = text;
      status.className = kind;
    };
    var emailError = document.getElementById("email-error");
    var emailOk = function () {
      return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(form.email.value.trim());
    };
    var setEmailError = function (text) {
      emailError.textContent = text;
      emailError.hidden = !text;
      if (text) form.email.setAttribute("aria-invalid", "true");
      else form.email.removeAttribute("aria-invalid");
    };
    // Checked when the person leaves the field (not while typing); cleared on the next keystroke.
    form.email.addEventListener("blur", function () {
      if (form.email.value.trim() && !emailOk()) setEmailError(T.email);
    });
    form.email.addEventListener("input", function () { setEmailError(""); });
    form.addEventListener("submit", function (e) {
      e.preventDefault();
      var email = form.email.value.trim();
      if (!emailOk()) {
        setEmailError(T.email);
        form.email.focus();
        return;
      }
      var checked = form.querySelectorAll("input[name=server]:checked");
      var servers = [];
      for (var i = 0; i < checked.length; i++) servers.push(checked[i].value);
      var data = {
        email: email,
        server: servers.join(","),
        pain: form.pain.value.trim(),
        tester: form.tester.checked ? "yes" : "no",
        _gotcha: form._gotcha.value
      };
      button.disabled = true;
      show(T.sending, "");
      fetch(FORM_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Accept": "application/json" },
        body: JSON.stringify(data)
      }).then(function (res) {
        if (!res.ok) throw new Error(String(res.status));
        form.reset();
        show(T.thanks, "ok");
      }).catch(function () {
        show(T.failed, "err");
      }).then(function () {
        button.disabled = false;
      });
    });
  }

  // Screenshots: swipe on a phone; on a computer, the arrow buttons scroll by one shot.
  var track = document.querySelector(".gallery-track");
  var nav = document.querySelector(".gallery-nav");
  if (track && nav) {
    var calm = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    var step = function () {
      var shot = track.querySelector(".shot");
      return shot ? shot.getBoundingClientRect().width + 26 : 280;
    };
    var update = function () {
      nav.hidden = track.scrollWidth <= track.clientWidth + 4;
    };
    nav.querySelector("[data-dir=prev]").addEventListener("click", function () {
      track.scrollBy({ left: -step(), behavior: calm ? "auto" : "smooth" });
    });
    nav.querySelector("[data-dir=next]").addEventListener("click", function () {
      track.scrollBy({ left: step(), behavior: calm ? "auto" : "smooth" });
    });
    window.addEventListener("resize", update);
    update();
  }

  // The phone menu and the language list (each a <details>) close after a tap on one of their links,
  // outside them, or Escape.
  var popups = document.querySelectorAll("details.menu, details.lang");
  Array.prototype.forEach.call(popups, function (menu) {
    menu.addEventListener("click", function (e) {
      if (e.target.closest("a")) menu.open = false;
    });
    document.addEventListener("click", function (e) {
      if (menu.open && !menu.contains(e.target)) menu.open = false;
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && menu.open) {
        menu.open = false;
        menu.querySelector("summary").focus();
      }
    });
  });

  // A language picked in the switcher is remembered in this browser only, so that js/lang.js opens
  // English pages in it (or, for English, stops following the browser's language).
  var langLinks = document.querySelectorAll(".lang-panel a[hreflang], .menu-langs a[hreflang], .footer-langs-list a[hreflang]");
  Array.prototype.forEach.call(langLinks, function (a) {
    a.addEventListener("click", function () {
      try { window.localStorage.setItem("ownmedia-lang", a.getAttribute("hreflang")); } catch (e) { /* storage blocked */ }
    });
  });

  // Copy buttons next to addresses and commands.
  var buttons = document.querySelectorAll("[data-copy]");
  for (var b = 0; b < buttons.length; b++) {
    buttons[b].addEventListener("click", function (e) {
      var btn = e.currentTarget;
      var target = document.getElementById(btn.getAttribute("data-copy"));
      if (!target || !navigator.clipboard) return;
      navigator.clipboard.writeText(target.textContent.trim()).then(function () {
        var label = btn.textContent;
        btn.textContent = T.copied;
        setTimeout(function () { btn.textContent = label; }, 1600);
      });
    });
  }
})();
