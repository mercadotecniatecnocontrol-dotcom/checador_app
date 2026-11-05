// ===== ÚNICO ARCHIVO A EDITAR =====
// Pega aquí la "anon public key" (o "publishable key") de Supabase: Project Settings → API.
window.APP_CONFIG = {
  SUPABASE_URL: "https://vlbyjoqessxcmkejcujp.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_18A7j06AwZqdw3gmqUDJHQ_Twu0t2a8",
  FUNCION_CHECKIN: "campo-checkin",
  PRECISION_MAX_M: 30,
  ZONA_HORARIA: "America/Chihuahua",
  EMPRESA: "Tecnocontrol",
  CENTRO_MAPA: [28.6353, -106.0889] // Chihuahua
};

// Paleta corporativa en RGB "R G B". Cambia solo estos valores.
window.APP_THEME = {
  light: {
    primary: "0 84 166", "on-primary": "255 255 255",
    secondary: "242 140 40", accent: "22 163 74",
    danger: "220 38 38", warning: "217 119 6",
    bg: "244 246 250", surface: "255 255 255",
    fg: "15 23 42", muted: "100 116 139", line: "226 232 240"
  },
  dark: {
    primary: "56 132 220",
    bg: "11 15 25", surface: "22 28 40",
    fg: "226 232 240", muted: "148 163 184", line: "45 55 72"
  }
};
