-- ProjetoAprovado — Etapa 2: análise de artigos e síntese

-- 1) Artigos enviados para um projeto
create table if not exists public.artigos (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid() references auth.users (id) on delete cascade,
  projeto_id     uuid not null references public.projetos (id) on delete cascade,
  nome_arquivo   text not null check (char_length(nome_arquivo) between 1 and 200),
  status         text not null default 'enviado' check (status in ('enviado', 'analisando', 'pronto', 'erro')),
  erro           text,
  referencia     text,
  autores        text[],
  ano            text,
  pagina_inicial int,
  ficha          jsonb,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists artigos_projeto_idx on public.artigos (projeto_id, created_at);
create index if not exists artigos_user_idx on public.artigos (user_id, status);
alter table public.artigos enable row level security;

drop policy if exists "artigos: dono le" on public.artigos;
drop policy if exists "artigos: dono cria em projeto proprio" on public.artigos;
drop policy if exists "artigos: dono apaga" on public.artigos;
create policy "artigos: dono le" on public.artigos for select to authenticated using (user_id = auth.uid());
create policy "artigos: dono cria em projeto proprio" on public.artigos for insert to authenticated
  with check (user_id = auth.uid() and exists (select 1 from public.projetos p where p.id = projeto_id and p.user_id = auth.uid()));
create policy "artigos: dono apaga" on public.artigos for delete to authenticated using (user_id = auth.uid());

revoke all on public.artigos from anon, authenticated;
grant select, delete on public.artigos to authenticated;
grant insert (projeto_id, nome_arquivo) on public.artigos to authenticated;
grant select, insert, update, delete on public.artigos to service_role;

drop trigger if exists artigos_updated_at on public.artigos;
create trigger artigos_updated_at before update on public.artigos
  for each row execute function public.tocar_updated_at();

-- 2) Textos do projeto (justificativa, referencial, referências, verificação)
alter table public.projetos add column if not exists textos jsonb;
alter table public.projetos add column if not exists sinteses int not null default 0;
grant update (titulo, estrutura, matriz, textos) on public.projetos to authenticated;

-- 3) Armazenamento privado dos artigos: pasta = id do usuário
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('artigos', 'artigos', false, 15728640, array['application/pdf'])
on conflict (id) do update set public = false, file_size_limit = 15728640, allowed_mime_types = array['application/pdf'];

drop policy if exists "artigos-pdf: dono envia" on storage.objects;
drop policy if exists "artigos-pdf: dono le" on storage.objects;
drop policy if exists "artigos-pdf: dono apaga" on storage.objects;
create policy "artigos-pdf: dono envia" on storage.objects for insert to authenticated
  with check (bucket_id = 'artigos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "artigos-pdf: dono le" on storage.objects for select to authenticated
  using (bucket_id = 'artigos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "artigos-pdf: dono apaga" on storage.objects for delete to authenticated
  using (bucket_id = 'artigos' and (storage.foldername(name))[1] = auth.uid()::text);

select 'etapa 2 pronta' as status;
