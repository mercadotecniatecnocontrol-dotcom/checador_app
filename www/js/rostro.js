// Reconocimiento facial en el dispositivo (gratis, sin servicios externos).
// Genera la "huella" (128 números) del rostro más grande de la imagen.
window.Rostro = (() => {
  const MODELOS = "https://cdn.jsdelivr.net/npm/@vladmandic/face-api@1.7.15/model/";
  let carga = null;
  function cargar() {
    if (!carga) {
      carga = (async () => {
        if (faceapi.tf?.ready) await faceapi.tf.ready();
        await Promise.all([
          faceapi.nets.tinyFaceDetector.loadFromUri(MODELOS),
          faceapi.nets.faceLandmark68Net.loadFromUri(MODELOS),
          faceapi.nets.faceRecognitionNet.loadFromUri(MODELOS),
        ]);
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
