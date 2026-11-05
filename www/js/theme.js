// Paleta Tecnocontrol (azul marino #1D2E73, rojo #E7402B). Valores en "R G B".
(function () {
  const T = {
    light: {
      primary: "29 46 115", "on-primary": "255 255 255",
      secondary: "231 64 43", accent: "22 163 74",
      danger: "220 38 38", warning: "217 119 6",
      bg: "243 245 250", surface: "255 255 255",
      fg: "15 23 42", muted: "100 116 139", line: "226 232 240"
    },
    dark: {
      primary: "29 46 115",
      bg: "10 14 28", surface: "21 27 45",
      fg: "226 232 240", muted: "148 163 184", line: "44 54 78"
    }
  };
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
