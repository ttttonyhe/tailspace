(function () {
  var root = document.documentElement;
  var isZh = (root.lang || "").toLowerCase().indexOf("zh") === 0;
  var saved = null;
  try {
    saved = localStorage.getItem("tailspace-theme");
  } catch (e) {}

  function prefersDark() {
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  }

  function applyTheme(mode) {
    if (mode === "light" || mode === "dark") {
      root.setAttribute("data-theme", mode);
    } else {
      root.removeAttribute("data-theme");
    }

    var effective = mode || (prefersDark() ? "dark" : "light");
    var sources = document.querySelectorAll("picture source[data-theme-source]");
    for (var i = 0; i < sources.length; i++) {
      var nextMedia = mode === "dark" ? "all" : mode === "light" ? "none" : "(prefers-color-scheme: dark)";
      sources[i].setAttribute("media", nextMedia);
    }

    var btn = document.getElementById("theme-toggle");
    if (btn) {
      if (isZh) {
        btn.textContent = effective === "dark" ? "浅色" : "深色";
        btn.setAttribute("aria-label", effective === "dark" ? "切换到浅色主题" : "切换到深色主题");
      } else {
        btn.textContent = effective === "dark" ? "light" : "dark";
        btn.setAttribute("aria-label", effective === "dark" ? "Switch to light theme" : "Switch to dark theme");
      }
    }
  }

  applyTheme(saved);

  var toggle = document.getElementById("theme-toggle");
  if (toggle) {
    toggle.addEventListener("click", function () {
      var current = root.getAttribute("data-theme") || (prefersDark() ? "dark" : "light");
      var next = current === "dark" ? "light" : "dark";
      try {
        localStorage.setItem("tailspace-theme", next);
      } catch (e) {}
      applyTheme(next);
    });
  }

  if (window.matchMedia) {
    var mq = window.matchMedia("(prefers-color-scheme: dark)");
    if (mq.addEventListener) {
      mq.addEventListener("change", function () {
        if (!root.getAttribute("data-theme")) {
          applyTheme(null);
        }
      });
    }
  }

  var boxes = document.querySelectorAll("[data-install-box]");
  for (var b = 0; b < boxes.length; b++) {
    (function (box) {
      var tabs = Array.prototype.slice.call(box.querySelectorAll("[role='tab']"));
      var panel = box.querySelector("[role='tabpanel']");
      var codeEl = box.querySelector("[data-cmd-text]");
      var noteEl = box.querySelector("[data-cmd-note]");
      var copyBtn = box.querySelector("[data-copy-btn]");
      var liveEl = box.querySelector("[data-copy-live]");
      var copyTimer = null;

      function selectTab(tab, focusTab) {
        for (var j = 0; j < tabs.length; j++) {
          var active = tabs[j] === tab;
          tabs[j].setAttribute("aria-selected", active ? "true" : "false");
          tabs[j].setAttribute("tabindex", active ? "0" : "-1");
        }
        if (panel && tab.id) panel.setAttribute("aria-labelledby", tab.id);
        if (codeEl) codeEl.textContent = tab.getAttribute("data-cmd") || "";
        if (noteEl && tab.getAttribute("data-note")) {
          noteEl.textContent = tab.getAttribute("data-note");
        }
        if (focusTab) tab.focus();
      }

      for (var t = 0; t < tabs.length; t++) {
        (function (idx) {
          tabs[idx].addEventListener("click", function () {
            selectTab(tabs[idx], false);
          });
          tabs[idx].addEventListener("keydown", function (e) {
            var nextIdx = null;
            if (e.key === "ArrowRight") nextIdx = (idx + 1) % tabs.length;
            else if (e.key === "ArrowLeft") nextIdx = (idx - 1 + tabs.length) % tabs.length;
            else if (e.key === "Home") nextIdx = 0;
            else if (e.key === "End") nextIdx = tabs.length - 1;
            if (nextIdx !== null) {
              e.preventDefault();
              selectTab(tabs[nextIdx], true);
            }
          });
        })(t);
      }

      if (copyBtn && codeEl) {
        copyBtn.addEventListener("click", function () {
          var text = codeEl.textContent || "";
          var original = copyBtn.getAttribute("data-label") || copyBtn.textContent;
          var doneLabel = copyBtn.getAttribute("data-copied") || "copied";

          function markCopied() {
            if (copyTimer) clearTimeout(copyTimer);
            copyBtn.textContent = doneLabel;
            copyBtn.classList.add("copied");
            if (liveEl) liveEl.textContent = isZh ? "安装命令已复制到剪贴板" : "Install command copied to clipboard";
            copyTimer = setTimeout(function () {
              copyBtn.textContent = original;
              copyBtn.classList.remove("copied");
              if (liveEl) liveEl.textContent = "";
              copyTimer = null;
            }, 1800);
          }

          function fallbackCopy() {
            var ta = document.createElement("textarea");
            ta.value = text;
            ta.setAttribute("readonly", "");
            ta.style.position = "fixed";
            ta.style.opacity = "0";
            document.body.appendChild(ta);
            ta.select();
            try {
              if (document.execCommand("copy")) markCopied();
            } catch (e) {}
            document.body.removeChild(ta);
          }

          if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(markCopied, fallbackCopy);
          } else {
            fallbackCopy();
          }
        });
      }
    })(boxes[b]);
  }
})();
