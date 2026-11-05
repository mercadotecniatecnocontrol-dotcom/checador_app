-- =====================================================================
-- CHECADOR DE CAMPO — esquema completo (correr TODO en SQL Editor)
-- Antes de correr: cambia el correo de la línea marcada con >>> abajo.
-- Es re-ejecutable (no duplica ni borra datos).
-- =====================================================================

-- ---------- Tablas ----------
create table if not exists public.campo_empleados (
  id                 text primary key,
  nombre             text not null,
  telefono           text,
  puesto             text,
  departamento       text,
  fecha_alta         date,
  ubicacion_nombre   text,
  lat                double precision,
  lng                double precision,
  radio_m            integer not null default 150 check (radio_m between 10 and 5000),
  foto_expediente    text,
  foto_actualizada_en timestamptz,
  activo             boolean not null default true,
  checa_campo        boolean not null default false,  -- solo estos pueden usar la app
  usuario_checador   text,                            -- No. de empleado en el Hikvision (vacío = mismo ID)
  creado_en          timestamptz not null default now(),
  actualizado_en     timestamptz not null default now()
);

create table if not exists public.campo_asistencias (
  id               uuid primary key default gen_random_uuid(),
  empleado_id      text not null references public.campo_empleados(id) on update cascade,
  empleado_nombre  text,
  lat              double precision not null,
  lng              double precision not null,
  precision_m      real not null,
  asig_lat         double precision,
  asig_lng         double precision,
  radio_m          integer,
  ubicacion_nombre text,
  distancia_m      real,
  similitud        real,
  foto_path        text not null,
  expediente_path  text,
  plataforma       text,
  estatus          text not null check (estatus in
                   ('APROBADO_AUTOMATICO','PENDIENTE_APROBACION_RH','APROBADO_RH','RECHAZADO')),
  causas           text[] not null default '{}',
  ts_servidor      timestamptz not null default now(),
  revisado_por     text,
  revisado_en      timestamptz,
  observaciones    text
);
alter table public.campo_empleados add column if not exists checa_campo boolean not null default false;
alter table public.campo_empleados add column if not exists usuario_checador text;
alter table public.campo_empleados add column if not exists huella real[];
alter table public.campo_asistencias add column if not exists distancia_rostro real;

create index if not exists campo_asis_ts_idx      on public.campo_asistencias (ts_servidor desc);
create index if not exists campo_asis_emp_idx     on public.campo_asistencias (empleado_id, ts_servidor desc);
create index if not exists campo_asis_estatus_idx on public.campo_asistencias (estatus);

create table if not exists public.campo_rh_admins (email text primary key);

-- >>> Correos que pueden entrar al panel de RH (usuarios de Supabase Auth). Agrega los que necesites.
insert into public.campo_rh_admins(email) values
  ('CAMBIA_ESTE_CORREO@tecnocontrol.com.mx')
on conflict do nothing;

-- ---------- Funciones y triggers ----------
create or replace function public.campo_es_rh() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.campo_rh_admins
                 where lower(email) = lower(coalesce(auth.jwt()->>'email','')));
$$;
revoke execute on function public.campo_es_rh() from public, anon;
grant  execute on function public.campo_es_rh() to authenticated;

-- Lista para el checador (solo ID, nombre y puesto de activos)
create or replace function public.campo_lista_empleados()
returns table (id text, nombre text, puesto text)
language sql stable security definer set search_path = public as $$
  select e.id, e.nombre, e.puesto from public.campo_empleados e where e.activo and e.checa_campo order by e.nombre;
$$;
revoke execute on function public.campo_lista_empleados() from public;
grant  execute on function public.campo_lista_empleados() to anon, authenticated;

-- Hora SIEMPRE del servidor
create or replace function public.campo_asis_ins_trg() returns trigger language plpgsql as $$
begin
  new.ts_servidor := now();
  new.revisado_por := null; new.revisado_en := null;
  return new;
end $$;
drop trigger if exists campo_asis_ins on public.campo_asistencias;
create trigger campo_asis_ins before insert on public.campo_asistencias
  for each row execute function public.campo_asis_ins_trg();

-- Revisión de RH: solo APROBADO_RH / RECHAZADO; quién y cuándo los pone el servidor
create or replace function public.campo_asis_upd_trg() returns trigger language plpgsql as $$
begin
  if new.estatus is distinct from old.estatus then
    if new.estatus not in ('APROBADO_RH','RECHAZADO') then
      raise exception 'Estatus no permitido: %', new.estatus;
    end if;
    new.revisado_en  := now();
    new.revisado_por := coalesce(auth.jwt()->>'email','sistema');
  end if;
  return new;
end $$;
drop trigger if exists campo_asis_upd on public.campo_asistencias;
create trigger campo_asis_upd before update on public.campo_asistencias
  for each row execute function public.campo_asis_upd_trg();

create or replace function public.campo_emp_upd_trg() returns trigger language plpgsql as $$
begin new.actualizado_en := now(); return new; end $$;
drop trigger if exists campo_emp_upd on public.campo_empleados;
create trigger campo_emp_upd before update on public.campo_empleados
  for each row execute function public.campo_emp_upd_trg();

-- ---------- Puente a la página de RH del Hikvision ----------
-- Cada checada APROBADA de la app (automática o por RH) se copia a checador_registros con origen 'app',
-- así aparece en la página de RH junto con las del Hikvision y entra en el saldo y el reporte de Excel.
-- Las pendientes o rechazadas NO se copian.
create or replace function public.campo_a_checador() returns trigger
language plpgsql security definer set search_path = public as $$
declare e public.campo_empleados%rowtype; u text;
begin
  if not (new.estatus in ('APROBADO_AUTOMATICO','APROBADO_RH')
          and (tg_op = 'INSERT' or old.estatus = 'PENDIENTE_APROBACION_RH')) then
    return new;
  end if;
  select * into e from public.campo_empleados where id = new.empleado_id;
  u := coalesce(nullif(e.usuario_checador, ''), e.id);

  insert into public.checador_personas (usuario_checador, nombre, departamento, puesto)
  values (u, e.nombre, e.departamento, e.puesto)
  on conflict (usuario_checador) do nothing;

  insert into public.checador_registros (usuario_checador, fecha_hora, metodo, dispositivo_serie, origen, datos)
  values (u, new.ts_servidor, 'app-gps-rostro', 'APP-CAMPO', 'app',
          jsonb_build_object('asistencia_id', new.id, 'lat', new.lat, 'lng', new.lng,
                             'precision_m', new.precision_m, 'estatus', new.estatus,
                             'similitud', new.similitud, 'plataforma', new.plataforma))
  on conflict (usuario_checador, fecha_hora) do nothing;
  return new;
end $$;
revoke execute on function public.campo_a_checador() from public, anon, authenticated;
drop trigger if exists campo_asis_a_checador on public.campo_asistencias;
create trigger campo_asis_a_checador after insert or update of estatus on public.campo_asistencias
  for each row execute function public.campo_a_checador();

-- ---------- RLS ----------
alter table public.campo_empleados   enable row level security;
alter table public.campo_asistencias enable row level security;
alter table public.campo_rh_admins   enable row level security;

revoke all on public.campo_empleados, public.campo_asistencias, public.campo_rh_admins from anon;
-- Las checadas solo las inserta la Edge Function (service role). RH solo cambia estatus y observaciones.
revoke insert, update, delete on public.campo_asistencias from authenticated;
grant  select on public.campo_asistencias to authenticated;
grant  update (estatus, observaciones) on public.campo_asistencias to authenticated;

drop policy if exists campo_emp_rh      on public.campo_empleados;
drop policy if exists campo_asis_rh_sel on public.campo_asistencias;
drop policy if exists campo_asis_rh_upd on public.campo_asistencias;
drop policy if exists campo_admins_sel  on public.campo_rh_admins;
create policy campo_emp_rh      on public.campo_empleados   for all    to authenticated using (public.campo_es_rh()) with check (public.campo_es_rh());
create policy campo_asis_rh_sel on public.campo_asistencias for select to authenticated using (public.campo_es_rh());
create policy campo_asis_rh_upd on public.campo_asistencias for update to authenticated using (public.campo_es_rh()) with check (public.campo_es_rh());
create policy campo_admins_sel  on public.campo_rh_admins   for select to authenticated using (public.campo_es_rh());

-- ---------- Realtime (notificación inmediata a RH) ----------
do $$ begin
  alter publication supabase_realtime add table public.campo_asistencias;
exception when duplicate_object then null; end $$;

-- ---------- Storage privado para fotos ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('campo-biometria','campo-biometria', false, 5242880, array['image/jpeg','image/png'])
on conflict (id) do nothing;

drop policy if exists campo_bio_rh_sel on storage.objects;
drop policy if exists campo_bio_rh_ins on storage.objects;
drop policy if exists campo_bio_rh_upd on storage.objects;
create policy campo_bio_rh_sel on storage.objects for select to authenticated
  using (bucket_id = 'campo-biometria' and public.campo_es_rh());
create policy campo_bio_rh_ins on storage.objects for insert to authenticated
  with check (bucket_id = 'campo-biometria' and public.campo_es_rh() and (storage.foldername(name))[1] = 'expediente');
create policy campo_bio_rh_upd on storage.objects for update to authenticated
  using (bucket_id = 'campo-biometria' and public.campo_es_rh() and (storage.foldername(name))[1] = 'expediente');

-- ---------- Carga inicial de personal (94 empleados) ----------
-- checa_campo = true solo para TÉCNICOS y AYUDANTES DE TÉCNICO (35). Ellos pueden checar en la app o en el Hikvision.
-- El resto solo en el Hikvision. RH puede cambiarlo en el panel.
-- usuario_checador vacío = se usa el mismo ID (003J, 042T…) como No. de empleado del Hikvision.
-- OJO: volver a correr este bloque restablece checa_campo según el puesto.
insert into public.campo_empleados (id, nombre, puesto, departamento, fecha_alta, checa_campo) values
('003J', 'ACEVES MOLINA IVAN ARGENIS', 'TECNICO', 'SERVICIOS CHIHUAHUA', '2023-07-29', true),
('042T', 'ACOSTA CONTRERAS CRISTINA JUDITH', 'GERENTE ADMINISTRATIVA', 'ADMINISTRATIVO', '2024-03-08', false),
('163T', 'APARICIO DOMINGA JUAN SANTIAGO', 'CARPINTERO', 'SERVICIOS CHIHUAHUA', '2026-10-10', false),
('021T', 'BARRAZA LUYA SAUL ISMAEL', 'TECNICO', 'SERVICIOS CHIHUAHUA', '2024-01-11', true),
('148T', 'BARRAZA VEGA JUAN DANIEL', 'OFICIAL', 'SERVICIOS CHIHUAHUA', '2026-08-08', false),
('006D', 'CALIXTO SANCHEZ RAFAEL', 'AYUDANTE TECNICO', 'MONTERREY', '2023-09-23', true),
('115T', 'CAMPOS GOMEZ ADA JAQUELINE', 'ADMINISTRATIVA', 'GESTORIA', '2026-01-23', false),
('124T', 'CANO CORRAL HECTOR ADRIAN', 'TECNICO', 'SERVICIOS CHIHUAHUA', '2026-05-08', true),
('122T', 'CARBAJAL TREJO CHRISTIAN ISAAC', 'AYUDANTE DE TECNICO', 'JUAREZ', '2026-04-25', true),
('135T', 'CARREON DE LEON ADRIAN ISAIAS', 'AYUDANTE DE TECNICO', 'SERVICIOS CHIHUAHUA', '2026-07-03', true),
('158T', 'CARRILLO AGUIRRE SHEILA ANAHI', 'AUXILIAR DE COMPRAS', 'ABASTECIMIENTO', '2026-10-08', false),
('020D', 'CASTRO MUÑOZ SAUL', 'AYUDANTE DE ALBAÑIL', 'CHIHUAHUA', '2025-12-03', false),
('113T', 'CHACON TERRAZAS LUCERO', 'ENCARGADA DE RR HH', 'ADMINISTRATIVO', '2026-01-19', false),
('147T', 'CHAVEZ ALMADER MAGALY JOHANA', 'AUXILIAR ADMVO DE OPERACIONES CUU', 'SERVICIOS CHIHUAHUA', '2026-08-10', false),
('116T', 'CHAVEZ ALVAREZ RUTH YADIRA', 'AUXILIAR DE COMPRAS', 'ABASTECIMIENTO', '2026-03-12', false),
('011D', 'CHAVEZ BARRAZA OSCAR IVAN', 'AYUDANTE DE ALBAÑIL', 'CHIHUAHUA', '2024-05-25', false),
('013D', 'CHAVEZ CHAVEZ IVAN', 'AYUDANTE DE ALBAÑIL', 'CHIHUAHUA', '2024-08-03', false),
('028T', 'CONTRERAS MORALES ELVA NIDIA', 'GERENTE DE ABASTECIMIENTO', 'ABASTECIMIENTO', '2022-10-21', false),
('006J', 'CORONADO VALENZUELA SOCORRO ANNET', 'INSPECTOR ELECTRICO', 'SERVICIOS CHIHUAHUA', '2026-01-20', false),
('161T', 'CRUZ JACINTO MIGUEL IGNACIO', 'ALBAÑIL', 'SERVICIOS CHIHUAHUA', '2026-10-10', false),
('004T', 'DE LA CRUZ EMILIO JULIO CESAR', 'TECNICO', 'MONTERREY', '2021-02-27', true),
('123T', 'DIAZ MACIAS JOSE LUIS REYNALDO', 'AYUDANTE DE TECNICO', 'SERVICIOS CHIHUAHUA', '2026-04-27', true),
('019T', 'DURSTEWITZ MAESE GUILLERMO', 'ASESOR COMERCIAL', 'VENTAS', '2021-08-05', false),
('117T', 'ESCALANTE JARAMILLO ANA KAREN', 'ADMINISTRATIVA', 'GESTORIA', '2026-03-17', false),
('150T', 'ESPINOZA OLIVAS EVA ALEJANDRA', 'ANALISTA DE INGRESOS', 'ADMINISTRATIVO', '2026-08-17', false),
('006T', 'ESTRADA GOMEZ ALAN ALBERTO', 'TECNICO', 'SERVICIOS CHIHUAHUA', '2019-09-28', true),
('108T', 'GARCIA LEDEZMA JESUS ALVARO', 'SUPERVISOR DE PROYECTOS', 'SERVICIOS CHIHUAHUA', '2025-10-06', false),
('033T', 'GARCIA MONTEMAYOR VERONICA JANETH', 'AUXILIAR ADTVA. MONTERREY', 'MONTERREY', '2023-07-01', false),
('140T', 'GARCIA PAYAN ALEJANDRO', 'MECANICO', 'ADMINISTRATIVO', '2026-07-30', false),
('142T', 'GARDEA GIRON OMAR RICARDO', 'ALMACENISTA', 'ABASTECIMIENTO', '2026-08-03', false),
('174T', 'GOMEZ MACIAS ANTONIO', 'ELECTRICISTA', 'SERVICIOS CHIHUAHUA', '2026-11-04', false),
('173T', 'GOMEZ VAZQUEZ JAHIR RAFAEL', 'ELECTRICISTA', 'SERVICIOS CHIHUAHUA', '2026-11-04', false),
('002T', 'GONZALEZ BABONOYABA RICARDO ANTONIO', 'TECNICO', 'SERVICIOS CHIHUAHUA', '2020-12-05', true),
('013T', 'GONZALEZ DELGADO ERICKA IDALY', 'ANALISTA DE EGRESOS', 'ADMINISTRATIVO', '2019-05-09', false),
('026T', 'GUERRERO GOMEZ JORGE', 'TECNICO', 'JUAREZ', '2022-06-09', true),
('039T', 'GUTIERREZ ALVARADO NAYRA DIDI', 'CONTADOR', 'ADMINISTRATIVO', '2023-11-22', false),
('022T', 'GUTIERREZ VILLARREAL DENISSE', 'GERENTE GESTORIA', 'GESTORIA', '2018-06-25', false),
('027T', 'GUZMAN MORALES FLOR IDALIA', 'AUXILIR ADTVA PARRAL', 'PARRAL', '2022-09-24', false),
('043T', 'GUZMAN NEAVE KENIA YADIRA', 'ADMINISTRATIVA', 'GESTORIA', '2024-04-15', false),
('106T', 'HERNANDEZ PEREZ RUBEN ALBERTO', 'TECNICO', 'SERVICIOS CHIHUAHUA', '2023-04-15', true),
('105T', 'HERNANDEZ PRIETO JOSUE', 'TECNICO', 'SERVICIOS CHIHUAHUA', '2025-09-01', true),
('160T', 'IGNACIO SANTOS ANTONIO', 'CARPINTERO', 'SERVICIOS CHIHUAHUA', '2026-10-10', false),
('136T', 'ITURRALDE GARCIA BLANCA PAOLA', 'ANALISTA DE CUENTAS POR PAGAR', 'ADMINISTRATIVO', '2026-07-13', false),
('166T', 'JIMENEZ MENA ALBERTO', 'AYUDANTE', 'SERVICIOS CHIHUAHUA', '2026-10-12', false),
('165T', 'JIMENEZ MENA ROBERTO CARLOS', 'FIERRERO', 'SERVICIOS CHIHUAHUA', '2026-10-12', false),
('168T', 'JUAN SANCHEZ DIEGO', 'AYUDANTE', 'SERVICIOS CHIHUAHUA', '2026-10-13', false),
('159T', 'JUAN SANCHEZ LORENZO', 'ALBAÑIL', 'SERVICIOS CHIHUAHUA', '2026-10-10', false),
('029T', 'LEAL MARTINEZ ROQUE MANUEL', 'TECNICO', 'MONTERREY', '2022-10-22', true),
('141T', 'LECHUGA VARGAS BRUNO', 'AYUDANTE DE TECNICO', 'SERVICIOS CHIHUAHUA', '2026-08-03', true),
('169T', 'LEOS CHARLES HUGO ALBERTO DE JESUS', 'TECNICO', 'MONTERREY', '2026-10-14', true),
('034T', 'LOPEZ AVILA SANDRA LUCERO', 'AUXILIAR ADMVO DE OPERACIONES CUU', 'SERVICIOS CHIHUAHUA', '2023-07-04', false),
('005D', 'LOPEZ DELGADO LUIS HUMBERTO', 'AYUDANTE TECNICO', 'CHIHUAHUA', '2023-01-07', true),
('138T', 'LUJAN PRADO KEVIN EDUARDO', 'DESARROLLADOR WEB', 'TRANSFORMACION DIGITAL Y MERCADOTECNIA', '2026-07-27', false),
('053T', 'LUNA ESPINOZA JAIME ROEL', 'TECNICO', 'SERVICIOS CHIHUAHUA', '2025-04-21', true),
('171T', 'MALDONADO GONZALEZ DANIEL EDUARDO', 'AYUDANTE DE TECNICO', 'SERVICIOS CHIHUAHUA', '2026-10-24', true),
('162T', 'MARIANO PEREZ JUAN', 'FIERRERO', 'SERVICIOS CHIHUAHUA', '2026-10-10', false),
('164T', 'MARTINEZ ARREGUIN JESUS', 'SEGURISTA', 'SERVICIOS CHIHUAHUA', '2026-10-10', false),
('155T', 'MARTINEZ ARREGUIN NAYN', 'RESIDENTE DE OBRA', 'SERVICIOS CHIHUAHUA', '2026-09-29', false),
('170T', 'MEDINA OLIVAS IVAN ALEJANDRO', 'AYUDANTE DE TECNICO', 'SERVICIOS CHIHUAHUA', '2026-10-24', true),
('014T', 'MENDOZA BECERRA SERGIO', 'PROYECTOS', 'SERVICIOS CHIHUAHUA', '2014-01-22', false),
('032T', 'MINJAREZ OCHOA ALBERTO ALAN', 'TECNICO', 'PARRAL', '2023-06-06', true),
('003T', 'MORALES MENDOZA TOMAS', 'MENSAJERO', 'ABASTECIMIENTO', '2021-01-05', false),
('157T', 'MORALES MORALES KARLA VERONICA', 'AUXILIAR DE IMAGEN', 'ADMINISTRATIVO', '2026-10-05', false),
('022D', 'MORENO MOLINA REYES', 'AYUDANTE DE ALBAÑIL', 'CHIHUAHUA', '2026-01-03', false),
('015T', 'MORIEL SAENZ RICARDO SALVADOR', 'SUPERVISOR PARRAL', 'PARRAL', '2021-05-22', false),
('132T', 'MORIEL VAZQUEZ OSCAR EDUARDO', 'AYUDANTE DE TECNICO', 'PARRAL', '2026-06-08', true),
('005T', 'MUÑOZ AVILA ROBERTO', 'TECNICO', 'SERVICIOS CHIHUAHUA', '2021-01-23', true),
('025T', 'MUÑOZ BLANCO LIZETH CRISTINA', 'ADMINISTRATIVA', 'GESTORIA', '2024-10-14', false),
('012T', 'NUÑEZ ALATORRE ULISES', 'TECNICO', 'SERVICIOS CHIHUAHUA', '2014-05-08', true),
('137T', 'NUÑEZ ARZOLA SAUL FERNANDO', 'TECNICO', 'SERVICIOS CHIHUAHUA', '2026-07-14', true),
('041T', 'PARRA BLANCO ZAIRA SIBEL', 'ENCARGADA DE LABORATORIO', 'GESTORIA', '2024-03-11', false),
('145T', 'PEINADO RIVERA JUAN CARLOS', 'TECNICO', 'PARRAL', '2026-08-05', true),
('167T', 'PEÑALOZA HERNANDEZ EDGAR IVAN', 'AYUDANTE', 'SERVICIOS CHIHUAHUA', '2026-10-12', false),
('024T', 'PEREZ ESPINDOLA RITA ISABEL', 'AUXILIAR ADMINISTRATIVO JRZ', 'JUAREZ', '2024-10-07', false),
('018T', 'PEREZ GARCIA MARTHA ARACELY', 'AUXILIAR ADMINISTRATIVO DE ALMACEN', 'ABASTECIMIENTO', '2021-08-03', false),
('008T', 'PORTILLO PORTILLO JOSE LUIS', 'AYUDANTE DE TECNICO', 'SERVICIOS CHIHUAHUA', '2019-06-15', true),
('112T', 'PRECIADO GRIJALVA GLEN IVAN', 'GERENTE', 'TRANSFORMACION DIGITAL Y MERCADOTECNIA', '2026-01-15', false),
('004D', 'REYES GONZALEZ PEDRO', 'AYUDANTE TECNICO', 'MONTERREY', '2021-09-14', true),
('151T', 'RIOS JACQUEZ DEREK', 'ALMACENISTA', 'ABASTECIMIENTO', '2026-08-26', false),
('099T', 'RIOS SALCIDO JOON OMAIRA', 'ASESOR COMERCIAL', 'VENTAS', '2025-07-03', false),
('131T', 'RODRIGUEZ RONQUILLO ALMA DELIA', 'AUXILIAR DE IMAGEN', 'ADMINISTRATIVO', '2026-06-01', false),
('154T', 'RODRIGUEZ SOTOMAYOR ERIKA GABRIELA', 'AUXILIAR DE MKT', 'TRANSFORMACION DIGITAL Y MERCADOTECNIA', '2026-09-28', false),
('002J', 'RUIZ OLMEDO NORMA IDALY', 'ADMINISTRATIVA', 'SERVICIOS CHIHUAHUA', '2023-07-06', false),
('037T', 'SALCEDO GARDEA FILIBERTO ISAI', 'TECNICO', 'PARRAL', '2023-09-04', true),
('152T', 'SANCHEZ CHAVEZ ALAN MARTIN', 'ENCARGADO DE TI', 'TRANSFORMACION DIGITAL Y MERCADOTECNIA', '2026-09-10', false),
('007T', 'SAUCEDO MARTINEZ IRVING ABRAHAM', 'SUEPRVISOR MONTERREY', 'MONTERREY', '2019-11-09', false),
('035T', 'SEPULVEDA MENDOZA IVAN ROBERTO', 'TECNICO', 'MONTERREY', '2023-07-12', true),
('010T', 'SOTO GONZALEZ BENITO', 'AYUDANTE DE TECNICO', 'JUAREZ', '2019-09-21', true),
('120T', 'TERRAZAS SERRANO FERNANDO', 'TECNICO', 'SERVICIOS CHIHUAHUA', '2026-04-06', true),
('143T', 'TORRES MUÑOZ MANUEL RICARDO', 'GERENTE DE OPERACIONES', 'SERVICIOS CHIHUAHUA', '2026-08-03', false),
('156T', 'TOVAR GONZALEZ ALDO SAID', 'DIBUJANTE PROYECTISTA', 'TRANSFORMACION DIGITAL Y MERCADOTECNIA', '2026-10-05', false),
('001T', 'URIBE MAESE JORGE ALBERTO', 'TECNICO', 'SERVICIOS CHIHUAHUA', '2023-12-26', true),
('095T', 'VALENZUELA LOPEZ JOSE LUIS', 'AYUDANTE DE TECNICO', 'JUAREZ', '2024-01-05', true),
('153T', 'VAZQUEZ SANDOVAL MARCO ARTURO', 'TECNICO ELECTROMECANICO', 'SERVICIOS CHIHUAHUA', '2026-09-24', true)
on conflict (id) do update set
  nombre = excluded.nombre, puesto = excluded.puesto, departamento = excluded.departamento,
  fecha_alta = excluded.fecha_alta, checa_campo = excluded.checa_campo;
