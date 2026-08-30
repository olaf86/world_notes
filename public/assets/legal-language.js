(() => {
  const supported = new Set(["ja", "en", "ko", "zh-Hans", "zh-Hant"]);
  const aliases = {
    "zh-CN": "zh-Hans",
    "zh-SG": "zh-Hans",
    "zh-TW": "zh-Hant",
    "zh-HK": "zh-Hant",
    "zh-MO": "zh-Hant",
  };

  function normalize(language) {
    if (!language) return null;
    if (supported.has(language)) return language;
    if (aliases[language]) return aliases[language];
    const base = language.split("-")[0];
    return supported.has(base) ? base : null;
  }

  const params = new URLSearchParams(window.location.search);
  const requested = normalize(params.get("lang"));
  const preferred = (navigator.languages || [navigator.language])
    .map(normalize)
    .find((language) => language !== null);
  const language = requested || preferred || "ja";

  document.documentElement.lang = language;
  document.querySelectorAll("[data-language-panel]").forEach((panel) => {
    panel.hidden = panel.dataset.languagePanel !== language;
  });
  document.querySelectorAll("[data-language-link]").forEach((link) => {
    if (link.dataset.languageLink === language) {
      link.setAttribute("aria-current", "page");
    } else {
      link.removeAttribute("aria-current");
    }
  });
  document.querySelectorAll("[data-language-target]").forEach((link) => {
    const target = link.dataset.languageTarget;
    link.href = `${target}?lang=${encodeURIComponent(language)}`;
  });
})();
