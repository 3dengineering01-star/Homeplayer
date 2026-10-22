// OwnMedia site: opens an English page in the visitor's language when the browser prefers German,
// French or Spanish and the page has that translation (its <link rel="alternate" hreflang>).
// Loaded in the <head> of English pages only, before anything is drawn, so the English page
// doesn't flash first. A language picked in the switcher wins (site.js remembers it in this
// browser's localStorage, nothing else is stored and nothing leaves the browser); English picked
// there means "never switch". Translated pages never send anyone anywhere.
(function () {
  "use strict";
  var saved = null;
  try { saved = window.localStorage.getItem("ownmedia-lang"); } catch (e) { /* storage blocked */ }
  if (saved === "en") return;

  var target = saved;
  if (!target) {
    var prefs = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || ""];
    for (var i = 0; i < prefs.length; i++) {
      var code = String(prefs[i]).slice(0, 2).toLowerCase();
      if (code === "en") return;  // English comes before any language the site has: stay
      if (document.querySelector('link[rel="alternate"][hreflang="' + code + '"]')) { target = code; break; }
    }
  }
  if (!target) return;
  var link = document.querySelector('link[rel="alternate"][hreflang="' + target + '"]');
  if (!link) return;
  // The same path on this host (the links hold the public address; a local preview stays local).
  var path = new URL(link.href).pathname;
  if (path !== location.pathname) location.replace(path + location.search + location.hash);
})();
