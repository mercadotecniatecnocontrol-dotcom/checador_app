(function () {
  const T = window.APP_THEME;
  const vars = o => Object.entries(o).map(([k, v]) => `--${k}:${v};`).join("");
  const st = document.createElement("style");
  st.textContent = `:root{${vars(T.light)}color-scheme:light}
@media (prefers-color-scheme: dark){:root{${vars(T.dark)}color-scheme:dark}}
body{background:rgb(var(--bg));color:rgb(var(--fg))}`;
  document.head.appendChild(st);
  const c = v => `rgb(var(--${v}) / <alpha-value>)`;
  window.tailwind.config = {
    theme: { extend: { colors: {
      primary: c("primary"), "on-primary": c("on-primary"), secondary: c("secondary"),
      accent: c("accent"), danger: c("danger"), warning: c("warning"),
      bg: c("bg"), surface: c("surface"), fg: c("fg"), muted: c("muted"), line: c("line")
    } } }
  };
})();
