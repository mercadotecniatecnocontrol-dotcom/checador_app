-- Checador de campo: reconocimiento facial en el celular (sin AWS).
-- Correr una sola vez en SQL Editor. Es seguro volver a correrlo.
alter table public.campo_empleados   add column if not exists huella real[];
alter table public.campo_asistencias add column if not exists distancia_rostro real;
