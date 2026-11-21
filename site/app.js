(function () {
  var root = document.documentElement;
  var isZh = (root.lang || "").toLowerCase().indexOf("zh") === 0;
  var saved = null;
  try {
    saved = localStorage.getItem("tailspace-theme");
  } catch (e) {}

  var ICON_COPY = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="5.5" y="5.5" width="8" height="8" rx="1.5"/><path d="M10.5 5.5V3.8A1.3 1.3 0 0 0 9.2 2.5H3.8A1.3 1.3 0 0 0 2.5 3.8v5.4a1.3 1.3 0 0 0 1.3 1.3h1.7"/></svg>';
  var ICON_CHECK = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3.5 8.5 6.5 11.5 12.5 4.5"/></svg>';

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

    var btns = document.querySelectorAll("[data-theme-toggle]");
    for (var b = 0; b < btns.length; b++) {
      if (isZh) {
        btns[b].textContent = effective === "dark" ? "浅色主题" : "深色主题";
        btns[b].setAttribute("aria-label", effective === "dark" ? "切换到浅色主题" : "切换到深色主题");
      } else {
        btns[b].textContent = effective === "dark" ? "Light mode" : "Dark mode";
        btns[b].setAttribute("aria-label", effective === "dark" ? "Switch to light theme" : "Switch to dark theme");
      }
    }
  }

  function copyText(text, onDone) {
    function fallback() {
      var ta = document.createElement("textarea");
      ta.value = text;
      ta.setAttribute("readonly", "");
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      try {
        if (document.execCommand("copy")) onDone();
      } catch (e) {}
      document.body.removeChild(ta);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(onDone, fallback);
    } else {
      fallback();
    }
  }

  applyTheme(saved);

  var toggles = document.querySelectorAll("[data-theme-toggle]");
  for (var t = 0; t < toggles.length; t++) {
    toggles[t].addEventListener("click", function () {
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
        if (!root.getAttribute("data-theme")) applyTheme(null);
      });
    }
  }

  // Mobile navigation drawer
  var menuBtn = document.querySelector("[data-menu-btn]");
  var drawer = document.querySelector("[data-mobile-drawer]");
  if (menuBtn && drawer) {
    function setOpen(open) {
      menuBtn.setAttribute("aria-expanded", open ? "true" : "false");
      if (open) drawer.classList.add("open");
      else drawer.classList.remove("open");
    }
    menuBtn.addEventListener("click", function () {
      setOpen(!drawer.classList.contains("open"));
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && drawer.classList.contains("open")) {
        setOpen(false);
        menuBtn.focus();
      }
    });
  }

  // Interactive terminal install switcher (WAI-ARIA tabs + dual action bar)
  var boxes = document.querySelectorAll("[data-install-box]");
  for (var k = 0; k < boxes.length; k++) {
    (function (box) {
      var tabs = Array.prototype.slice.call(box.querySelectorAll("[role='tab']"));
      var panel = box.querySelector("[role='tabpanel']");
      var commentEl = box.querySelector("[data-cmd-comment]");
      var codeEl = box.querySelector("[data-cmd-text]");
      var copyBtn = box.querySelector("[data-copy-btn]");
      var liveEl = box.querySelector("[data-copy-live]");
      var copyTimer = null;

      function setCopyState(copied) {
        if (!copyBtn) return;
        var label = copied
          ? (copyBtn.getAttribute("data-copied") || (isZh ? "已复制安装命令" : "Copied install command"))
          : (copyBtn.getAttribute("data-label") || (isZh ? "复制安装命令" : "Copy install command"));
        copyBtn.innerHTML = "<span>" + label + "</span>" + (copied ? ICON_CHECK : ICON_COPY);
        if (copied) copyBtn.classList.add("copied");
        else copyBtn.classList.remove("copied");
      }

      setCopyState(false);

      function selectTab(tab, focusTab) {
        for (var j = 0; j < tabs.length; j++) {
          var active = tabs[j] === tab;
          tabs[j].setAttribute("aria-selected", active ? "true" : "false");
          tabs[j].setAttribute("tabindex", active ? "0" : "-1");
        }
        if (panel && tab.id) panel.setAttribute("aria-labelledby", tab.id);
        if (panel) {
          panel.classList.add("swapping");
          setTimeout(function () {
            if (commentEl) commentEl.textContent = "# " + (tab.getAttribute("data-note") || "");
            if (codeEl) codeEl.textContent = tab.getAttribute("data-cmd") || "";
            panel.classList.remove("swapping");
          }, 70);
        }
        if (focusTab) tab.focus();
      }

      for (var ti = 0; ti < tabs.length; ti++) {
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
        })(ti);
      }

      if (copyBtn && codeEl) {
        copyBtn.addEventListener("click", function () {
          copyText(codeEl.textContent || "", function () {
            if (copyTimer) clearTimeout(copyTimer);
            setCopyState(true);
            if (liveEl) liveEl.textContent = isZh ? "安装命令已复制到剪贴板" : "Install command copied to clipboard";
            copyTimer = setTimeout(function () {
              setCopyState(false);
              if (liveEl) liveEl.textContent = "";
              copyTimer = null;
            }, 1800);
          });
        });
      }
    })(boxes[k]);
  }

  // Copy buttons for standalone <pre><code> blocks
  var pres = document.querySelectorAll("main pre");
  for (var p = 0; p < pres.length; p++) {
    (function (pre) {
      var code = pre.querySelector("code");
      if (!code) return;
      var wrap = document.createElement("div");
      wrap.className = "code-wrap";
      pre.parentNode.insertBefore(wrap, pre);
      wrap.appendChild(pre);

      var btn = document.createElement("button");
      btn.type = "button";
      btn.className = "pre-copy";
      var label = isZh ? "复制" : "copy";
      var done = isZh ? "已复制" : "copied";
      btn.textContent = label;
      btn.setAttribute("aria-label", isZh ? "复制代码" : "Copy code snippet");
      var timer = null;

      btn.addEventListener("click", function () {
        copyText(code.textContent || "", function () {
          if (timer) clearTimeout(timer);
          btn.textContent = done;
          btn.classList.add("copied");
          timer = setTimeout(function () {
            btn.textContent = label;
            btn.classList.remove("copied");
            timer = null;
          }, 1600);
        });
      });

      wrap.appendChild(btn);
    })(pres[p]);
  }
})();
