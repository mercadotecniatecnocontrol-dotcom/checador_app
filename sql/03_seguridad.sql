-- Checador de campo: celular vinculado por empleado + registro de prueba de vida.
-- Correr una sola vez en SQL Editor. Es seguro volver a correrlo.
create table if not exists public.campo_dispositivos (
  empleado_id    text primary key references public.campo_empleados(id) on update cascade on delete cascade,
  dispositivo_id text not null unique,
  plataforma     text,
  modelo         text,
  vinculado_en   timestamptz not null default now(),
  ultimo_uso     timestamptz
);
alter table public.campo_dispositivos enable row level security;
revoke all on public.campo_dispositivos from anon;
drop policy if exists campo_disp_rh_sel on public.campo_dispositivos;
drop policy if exists campo_disp_rh_del on public.campo_dispositivos;
create policy campo_disp_rh_sel on public.campo_dispositivos for select to authenticated using (public.campo_es_rh());
create policy campo_disp_rh_del on public.campo_dispositivos for delete to authenticated using (public.campo_es_rh());

alter table public.campo_asistencias add column if not exists dispositivo_id text;
alter table public.campo_asistencias add column if not exists prueba_vida boolean;
