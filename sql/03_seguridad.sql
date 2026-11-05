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

-- Al dar de baja (Activo o Campo desmarcado) se libera su celular automáticamente.
create or replace function public.campo_liberar_por_baja() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (new.activo = false or new.checa_campo = false)
     and (old.activo is distinct from new.activo or old.checa_campo is distinct from new.checa_campo) then
    delete from public.campo_dispositivos where empleado_id = new.id;
  end if;
  return new;
end $$;
revoke execute on function public.campo_liberar_por_baja() from public, anon, authenticated;
drop trigger if exists campo_emp_baja on public.campo_empleados;
create trigger campo_emp_baja after update of activo, checa_campo on public.campo_empleados
  for each row execute function public.campo_liberar_por_baja();

-- La app pregunta al abrir si el técnico guardado en el celular sigue vigente.
-- Responde: 'baja' | 'vinculado' | 'otro' (celular de otro técnico) | 'libre' (sin vincular o liberado por RH)
create or replace function public.campo_estado_dispositivo(p_dispositivo text, p_empleado text)
returns text language sql stable security definer set search_path = public as $$
  select case
    when not exists (select 1 from public.campo_empleados e
                     where e.id = upper(p_empleado) and e.activo and e.checa_campo) then 'baja'
    when exists (select 1 from public.campo_dispositivos d
                 where d.dispositivo_id = p_dispositivo and d.empleado_id = upper(p_empleado)) then 'vinculado'
    when exists (select 1 from public.campo_dispositivos d where d.dispositivo_id = p_dispositivo) then 'otro'
    else 'libre' end;
$$;
revoke execute on function public.campo_estado_dispositivo(text, text) from public;
grant  execute on function public.campo_estado_dispositivo(text, text) to anon, authenticated;
