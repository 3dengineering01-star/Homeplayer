// OwnMedia site: the Google Play sign-up form, the screenshot buttons and the copy buttons. Nothing else:
// no tracking, no cookies, nothing loaded from other sites. Each part runs only where its
// element is on the page.

(function () {
  "use strict";

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
      if (form.email.value.trim() && !emailOk()) setEmailError("Enter an email like name@example.com.");
    });
    form.email.addEventListener("input", function () { setEmailError(""); });
    form.addEventListener("submit", function (e) {
      e.preventDefault();
      var email = form.email.value.trim();
      if (!emailOk()) {
        setEmailError("Enter an email like name@example.com.");
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
      show("Sending…", "");
      fetch(FORM_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Accept": "application/json" },
        body: JSON.stringify(data)
      }).then(function (res) {
        if (!res.ok) throw new Error(String(res.status));
        form.reset();
        show("Thanks! We'll write once OwnMedia is on Google Play.", "ok");
      }).catch(function () {
        show("The sign-up didn’t reach us. Check your connection, then select Notify me again.", "err");
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

  // The phone menu (a <details>) closes after a tap on one of its links, outside it, or Escape.
  var menu = document.querySelector(".menu");
  if (menu) {
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
  }

  // Copy buttons next to addresses and commands.
  var buttons = document.querySelectorAll("[data-copy]");
  for (var b = 0; b < buttons.length; b++) {
    buttons[b].addEventListener("click", function (e) {
      var btn = e.currentTarget;
      var target = document.getElementById(btn.getAttribute("data-copy"));
      if (!target || !navigator.clipboard) return;
      navigator.clipboard.writeText(target.textContent.trim()).then(function () {
        var label = btn.textContent;
        btn.textContent = "Copied";
        setTimeout(function () { btn.textContent = label; }, 1600);
      });
    });
  }
})();
