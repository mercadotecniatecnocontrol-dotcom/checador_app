// Reconocimiento facial en el dispositivo (gratis, sin servicios externos).
// Genera la "huella" (128 números) del rostro más grande de la imagen.
// Los modelos viven en este mismo sitio (./models); el CDN queda solo de respaldo.
// Si el motor gráfico (WebGL) del celular se traba, cambia al motor normal (CPU).
window.Rostro = (() => {
  const MODELOS = "./models/";
  const MODELOS_CDN = "https://cdn.jsdelivr.net/npm/@vladmandic/face-api@1.7.15/model/";
  let carga = null;

  const conTiempo = (p, ms, msg) =>
    Promise.race([p, new Promise((_, rej) => setTimeout(() => rej(new Error(msg)), ms))]);

  async function motor(nombre) {
    const tf = faceapi.tf;
    if (!tf) return;
    await conTiempo(Promise.resolve(tf.setBackend(nombre)), 10000, "motor");
    await conTiempo(tf.ready(), 10000, "motor");
  }
  const modelos = base => Promise.all([
    faceapi.nets.tinyFaceDetector.loadFromUri(base),
    faceapi.nets.faceLandmark68Net.loadFromUri(base),
    faceapi.nets.faceRecognitionNet.loadFromUri(base),
  ]);
  async function intento(nombreMotor) {
    await motor(nombreMotor);
    try { await conTiempo(modelos(MODELOS), 45000, "descarga"); }
    catch { await conTiempo(modelos(MODELOS_CDN), 45000, "descarga"); }
    // Prueba rápida para confirmar que el motor sí calcula en este celular.
    const c = document.createElement("canvas"); c.width = c.height = 96;
    await conTiempo(faceapi.detectAllFaces(c, new faceapi.TinyFaceDetectorOptions({ inputSize: 128 })), 15000, "prueba");
  }
  function cargar() {
    if (!carga) {
      carga = (async () => {
        if (typeof faceapi === "undefined") throw new Error("script");
        try { await intento("webgl"); }
        catch { await intento("cpu"); }
      })();
      carga.catch(() => { carga = null; });
    }
    return carga;
  }
  async function huella(fuente) {
    await cargar();
    const dets = await faceapi
      .detectAllFaces(fuente, new faceapi.TinyFaceDetectorOptions({ inputSize: 416, scoreThreshold: 0.45 }))
      .withFaceLandmarks().withFaceDescriptors();
    if (!dets.length) return null;
    dets.sort((a, b) => b.detection.box.area - a.detection.box.area);
    return Array.from(dets[0].descriptor, v => Math.round(v * 1e6) / 1e6);
  }
  return { cargar, huella };
})();
