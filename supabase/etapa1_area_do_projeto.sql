-- ProjetoAprovado — Etapa 1: área do projeto (login, projetos, acessos, editais)

-- 1) Acessos (passes). Só o servidor/admin grava; o usuário lê o próprio.
create table if not exists public.acessos (
  user_id      uuid primary key references auth.users (id) on delete cascade,
  plano        text not null check (plano in ('beta', 'edital_unico', 'pesquisador')),
  editais_max  int  not null default 1,
  artigos_max  int  not null default 15,
  valido_ate   timestamptz not null,
  created_at   timestamptz not null default now()
);
alter table public.acessos enable row level security;
drop policy if exists "usuario le o proprio acesso" on public.acessos;
create policy "usuario le o proprio acesso" on public.acessos
  for select to authenticated using (user_id = auth.uid());

-- 2) Projetos. Cada usuário só vê e edita os próprios.
create table if not exists public.projetos (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  titulo        text not null check (char_length(titulo) between 2 and 200),
  nivel         text not null check (nivel in ('Mestrado', 'Doutorado')),
  area          text not null check (char_length(area) between 2 and 120),
  tema          text not null check (char_length(tema) between 3 and 2000),
  edital_nome   text,
  status        text not null default 'rascunho' check (status in ('rascunho', 'gerando', 'pronto', 'erro')),
  geracoes      int  not null default 0,
  edital_resumo jsonb,
  estrutura     jsonb,
  matriz        jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists projetos_user_idx on public.projetos (user_id, updated_at desc);
alter table public.projetos enable row level security;

drop policy if exists "dono le" on public.projetos;
drop policy if exists "dono cria" on public.projetos;
drop policy if exists "dono edita" on public.projetos;
drop policy if exists "dono apaga" on public.projetos;
create policy "dono le"    on public.projetos for select to authenticated using (user_id = auth.uid());
create policy "dono cria"  on public.projetos for insert to authenticated with check (user_id = auth.uid());
create policy "dono edita" on public.projetos for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "dono apaga" on public.projetos for delete to authenticated using (user_id = auth.uid());

-- O usuário não pode mexer nos campos controlados pelo servidor (status, geracoes, edital_resumo, dono)
revoke all on public.projetos from anon, authenticated;
grant select, delete on public.projetos to authenticated;
grant insert (titulo, nivel, area, tema, edital_nome) on public.projetos to authenticated;
grant update (titulo, estrutura, matriz) on public.projetos to authenticated;

create or replace function public.tocar_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
drop trigger if exists projetos_updated_at on public.projetos;
create trigger projetos_updated_at before update on public.projetos
  for each row execute function public.tocar_updated_at();

-- 3) Registro de gerações (controle de custo). Só o servidor.
create table if not exists public.geracoes (
  id             bigint generated always as identity primary key,
  created_at     timestamptz not null default now(),
  user_id        uuid references auth.users (id) on delete set null,
  projeto_id     uuid,
  tipo           text not null,
  status         text not null check (status in ('ok', 'erro')),
  erro           text,
  tokens_entrada int,
  tokens_saida   int
);
create index if not exists geracoes_user_idx on public.geracoes (user_id, created_at);
alter table public.geracoes enable row level security;

-- 4) Permissões do servidor (o projeto foi criado sem grants automáticos)
revoke all on public.acessos, public.geracoes from anon, authenticated;
grant select on public.acessos to authenticated;
grant usage on schema public to authenticated, service_role;
grant select, insert, update, delete on public.acessos, public.projetos, public.geracoes to service_role;

-- 5) Armazenamento privado dos editais: pasta = id do usuário
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('editais', 'editais', false, 10485760, array['application/pdf'])
on conflict (id) do update set public = false, file_size_limit = 10485760, allowed_mime_types = array['application/pdf'];

drop policy if exists "editais: dono envia" on storage.objects;
drop policy if exists "editais: dono le" on storage.objects;
drop policy if exists "editais: dono atualiza" on storage.objects;
drop policy if exists "editais: dono apaga" on storage.objects;
create policy "editais: dono envia" on storage.objects for insert to authenticated
  with check (bucket_id = 'editais' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "editais: dono le" on storage.objects for select to authenticated
  using (bucket_id = 'editais' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "editais: dono atualiza" on storage.objects for update to authenticated
  using (bucket_id = 'editais' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "editais: dono apaga" on storage.objects for delete to authenticated
  using (bucket_id = 'editais' and (storage.foldername(name))[1] = auth.uid()::text);

select 'etapa 1 pronta' as status;
