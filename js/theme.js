// Paleta tomada del logo Tecnocontrol: azul #2B3A8C, índigo #2A0F5C, rojo #CC1028, negro #1F1F1F. Valores en "R G B".
(function () {
  const T = {
    light: {
      primary: "43 58 140", "on-primary": "255 255 255", profundo: "42 15 92",
      secondary: "204 16 40", accent: "22 163 74",
      danger: "220 38 38", warning: "217 119 6",
      bg: "243 245 250", surface: "255 255 255",
      fg: "31 31 31", muted: "100 105 120", line: "226 228 236"
    },
    dark: {
      primary: "72 92 196",
      bg: "12 12 20", surface: "26 27 38",
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
      primary: c("primary"), "on-primary": c("on-primary"), profundo: c("profundo"), secondary: c("secondary"),
      accent: c("accent"), danger: c("danger"), warning: c("warning"),
      bg: c("bg"), surface: c("surface"), fg: c("fg"), muted: c("muted"), line: c("line")
    } } }
  };
})();
