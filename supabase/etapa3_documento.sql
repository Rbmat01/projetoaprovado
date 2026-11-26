-- ProjetoAprovado — Etapa 3: cronograma e dados do documento final (.docx)
alter table public.projetos add column if not exists cronograma jsonb;
alter table public.projetos add column if not exists documento jsonb;

-- O usuário pode editar só as colunas liberadas (as anteriores continuam valendo)
grant update (cronograma, documento) on public.projetos to authenticated;

select 'etapa 3 pronta' as status;
