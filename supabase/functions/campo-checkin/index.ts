// Edge Function: campo-checkin
// Valida GPS (Haversine, solo si el empleado tiene sitio fijo) + rostro (huella facial generada en el celular)
// y registra la checada con hora del servidor. No usa servicios externos.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { decodeBase64 } from "jsr:@std/encoding@1.0.5/base64";

const PRECISION_MAX = 30;   // metros
const UMBRAL_ROSTRO = 75;   // % de coincidencia mínima
const ESPERA_MIN = 3;       // minutos entre checadas del mismo empleado
const BUCKET = "campo-biometria";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

function haversine(lat1: number, lon1: number, lat2: number, lon2: number) {
  const R = 6371000, r = Math.PI / 180;
  const dLat = (lat2 - lat1) * r, dLon = (lon2 - lon1) * r;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * r) * Math.cos(lat2 * r) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

const esHuella = (h: unknown): h is number[] =>
  Array.isArray(h) && h.length === 128 && h.every(v => typeof v === "number" && Number.isFinite(v) && Math.abs(v) < 2);

// Distancia euclidiana entre huellas (face-api): 0 = idénticas; < 0.5 = misma persona.
function distanciaHuellas(a: number[], b: number[]) {
  let s = 0;
  for (let i = 0; i < 128; i++) s += (a[i] - b[i]) ** 2;
  return Math.sqrt(s);
}
// Convierte la distancia a % de coincidencia: 0.35 → 100%, 0.50 → 75% (umbral), 0.95 → 0%.
const aPorcentaje = (d: number) => Math.max(0, Math.min(100, 100 - (d - 0.35) * (25 / 0.15)));

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);

  let b: Record<string, unknown>;
  try { b = await req.json(); } catch { return json({ error: "Solicitud inválida" }, 400); }

  // La hora del dispositivo NO se usa: la pone el servidor.
  const id = String(b.idEmpleado ?? "").trim().toUpperCase();
  const lat = Number(b.latitud), lng = Number(b.longitud), precision = Number(b.precision);
  const plataforma = String(b.plataforma ?? "web").slice(0, 20);
  const fotoB64 = String(b.fotoBase64 ?? "").split(",").pop() ?? "";
  const huella = esHuella(b.huella) ? b.huella : null;

  if (!id || ![lat, lng, precision].every(Number.isFinite) || Math.abs(lat) > 90 || Math.abs(lng) > 180)
    return json({ error: "Datos incompletos" }, 400);
  if (precision > PRECISION_MAX)
    return json({ error: `Precisión GPS insuficiente (${Math.round(precision)} m). Debe ser menor a ${PRECISION_MAX} m.` }, 422);
  if (fotoB64.length < 2000 || fotoB64.length > 7_000_000) return json({ error: "Foto inválida" }, 400);

  let bytes: Uint8Array;
  try { bytes = decodeBase64(fotoB64); } catch { return json({ error: "Foto inválida" }, 400); }
  if (!(bytes[0] === 0xff && bytes[1] === 0xd8)) return json({ error: "La foto debe ser JPEG" }, 400);

  const { data: emp, error: eEmp } = await sb.from("campo_empleados").select("*").eq("id", id).eq("activo", true).maybeSingle();
  if (eEmp) return json({ error: "Error al consultar empleado" }, 500);
  if (!emp) return json({ error: "Empleado no encontrado o inactivo" }, 404);
  if (!emp.checa_campo) return json({ error: "Este empleado no está autorizado para checar en campo" }, 403);

  const { data: reciente } = await sb.from("campo_asistencias").select("id")
    .eq("empleado_id", id).gte("ts_servidor", new Date(Date.now() - ESPERA_MIN * 60_000).toISOString()).limit(1);
  if (reciente?.length) return json({ error: `Ya registraste una checada hace menos de ${ESPERA_MIN} minutos.` }, 429);

  const hoy = new Date().toISOString().slice(0, 10);
  const fotoPath = `checadas/${id}/${hoy}/${crypto.randomUUID()}.jpg`;
  const up = await sb.storage.from(BUCKET).upload(fotoPath, bytes, { contentType: "image/jpeg" });
  if (up.error) return json({ error: "No se pudo guardar la foto" }, 500);

  const causas: string[] = [];

  // 1) Ubicación: siempre se guarda la del celular. Solo si tiene sitio fijo se valida la distancia.
  let distancia: number | null = null;
  if (emp.lat != null && emp.lng != null) {
    distancia = haversine(emp.lat, emp.lng, lat, lng);
    if (distancia > emp.radio_m)
      causas.push(`Ubicación fuera de rango a ${Math.round(distancia)} m (radio permitido ${emp.radio_m} m)`);
  }

  // 2) Rostro
  let similitud: number | null = null, distRostro: number | null = null;
  if (!emp.foto_expediente || !esHuella(emp.huella)) {
    causas.push("Empleado sin foto de expediente (no enrolado)");
  } else if (!huella) {
    causas.push("No se detectó un rostro en la foto");
  } else {
    distRostro = distanciaHuellas(emp.huella, huella);
    similitud = aPorcentaje(distRostro);
    if (similitud < UMBRAL_ROSTRO) causas.push(`Rostro no coincide (${similitud.toFixed(1)}%)`);
  }

  // 3) Estatus
  const estatus = causas.length ? "PENDIENTE_APROBACION_RH" : "APROBADO_AUTOMATICO";

  const { data, error } = await sb.from("campo_asistencias").insert({
    empleado_id: id, empleado_nombre: emp.nombre,
    lat, lng, precision_m: precision,
    asig_lat: emp.lat, asig_lng: emp.lng, radio_m: emp.radio_m, ubicacion_nombre: emp.ubicacion_nombre,
    distancia_m: distancia, similitud, distancia_rostro: distRostro,
    foto_path: fotoPath, expediente_path: emp.foto_expediente,
    plataforma, estatus, causas,
  }).select("id, estatus, causas, ts_servidor, distancia_m, similitud").single();

  if (error) { console.error(error); return json({ error: "No se pudo registrar la checada" }, 500); }
  return json({ ...data, nombre: emp.nombre });
});
