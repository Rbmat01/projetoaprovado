// ProjetoAprovado — Edge Function "admin"
// Painel de administração: só responde a e-mails da lista ADMINS (validados pelo login do Supabase).
// Ações: "resumo" (leads, estruturas, projetos, passes, gasto de IA), "liberar_beta", "revogar".
// Configuração: "Verify JWT" desligado (o código valida o usuário e o e-mail).

import { createClient } from "npm:@supabase/supabase-js@2";

const ADMINS = ["bezerra.ronaldo@gmail.com"];
const ORIGENS_PERMITIDAS = ["https://rbmat01.github.io"];
// Preço do Claude Sonnet 5.5 (US$ por milhão de tokens) — atualizar se mudar
const PRECO_ENTRADA = 2;
const PRECO_SAIDA = 10;

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

function cors(origin: string | null) {
  const o = origin && ORIGENS_PERMITIDAS.includes(origin) ? origin : ORIGENS_PERMITIDAS[0];
  return {
    "Access-Control-Allow-Origin": o,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Vary": "Origin",
  };
}
const json = (b: unknown, s: number, o: string | null) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors(o), "Content-Type": "application/json; charset=utf-8" } });

async function todosUsuarios() {
  const lista: { id: string; email?: string; created_at: string; last_sign_in_at?: string }[] = [];
  for (let page = 1; page <= 20; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    lista.push(...data.users.map((u) => ({ id: u.id, email: u.email, created_at: u.created_at, last_sign_in_at: u.last_sign_in_at })));
    if (data.users.length < 1000) break;
  }
  return lista;
}

// deno-lint-ignore no-explicit-any
const custo = (linhas: any[]) =>
  linhas.reduce((t, l) => t + ((l.tokens_entrada ?? 0) * PRECO_ENTRADA + (l.tokens_saida ?? 0) * PRECO_SAIDA) / 1e6, 0);

Deno.serve(async (req) => {
  const origin = req.headers.get("origin");
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(origin) });
  if (req.method !== "POST") return json({ ok: false, motivo: "Método não permitido." }, 405, origin);
  if (!origin || !ORIGENS_PERMITIDAS.includes(origin)) return json({ ok: false, motivo: "Origem não permitida." }, 403, origin);

  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: u } = await admin.auth.getUser(token);
  const email = u?.user?.email?.toLowerCase() ?? "";
  if (!u?.user || !ADMINS.includes(email)) return json({ ok: false, motivo: "Acesso restrito ao administrador." }, 403, origin);

  const corpo = await req.json().catch(() => ({}));
  const acao = corpo.acao;

  try {
    if (acao === "resumo") {
      const agora = Date.now();
      const desde30 = new Date(agora - 30 * 864e5).toISOString();
      const hojeInicio = new Date(new Date().toISOString().slice(0, 10) + "T03:00:00Z"); // meia-noite em Brasília
      if (hojeInicio.getTime() > agora) hojeInicio.setUTCDate(hojeInicio.getUTCDate() - 1);
      const hoje = hojeInicio.toISOString();

      const [leads, estruturas, geracoes, projetos, acessos, usuarios] = await Promise.all([
        admin.from("leads").select("id,created_at,nivel,area,tema,contato,origem").order("created_at", { ascending: false }).limit(200),
        admin.from("estruturas").select("id,created_at,nivel,area,contato,status,erro,tokens_entrada,tokens_saida").gte("created_at", desde30).order("created_at", { ascending: false }),
        admin.from("geracoes").select("id,created_at,user_id,status,erro,tokens_entrada,tokens_saida").gte("created_at", desde30).order("created_at", { ascending: false }),
        admin.from("projetos").select("id,user_id,titulo,nivel,area,status,geracoes,updated_at").order("updated_at", { ascending: false }).limit(200),
        admin.from("acessos").select("*").order("valido_ate", { ascending: false }),
        todosUsuarios(),
      ]);
      for (const r of [leads, estruturas, geracoes, projetos, acessos]) if (r.error) throw r.error;

      const emailDe = new Map(usuarios.map((x) => [x.id, x.email ?? ""]));
      const est = estruturas.data ?? [], ger = geracoes.data ?? [];
      const deHoje = <T extends { created_at: string }>(l: T[]) => l.filter((x) => x.created_at >= hoje);

      return json({
        ok: true,
        numeros: {
          leads_total: (leads.data ?? []).length,
          usuarios_total: usuarios.length,
          passes_ativos: (acessos.data ?? []).filter((a) => new Date(a.valido_ate) > new Date()).length,
          projetos_total: (projetos.data ?? []).length,
          estruturas_hoje: deHoje(est).length,
          geracoes_hoje: deHoje(ger).length,
          custo_hoje_usd: custo([...deHoje(est), ...deHoje(ger)]),
          custo_30d_usd: custo([...est, ...ger]),
          erros_30d: [...est, ...ger].filter((x) => x.status === "erro").length,
        },
        leads: leads.data,
        estruturas: est.slice(0, 100),
        projetos: (projetos.data ?? []).map((p) => ({ ...p, email: emailDe.get(p.user_id) ?? "" })),
        passes: (acessos.data ?? []).map((a) => ({ ...a, email: emailDe.get(a.user_id) ?? "" })),
        usuarios: usuarios.map((x) => ({ email: x.email, created_at: x.created_at, last_sign_in_at: x.last_sign_in_at })),
      }, 200, origin);
    }

    if (acao === "liberar_beta") {
      const alvo = String(corpo.email ?? "").trim().toLowerCase();
      const dias = Math.min(Math.max(parseInt(corpo.dias ?? "60", 10) || 60, 1), 365);
      const editais = Math.min(Math.max(parseInt(corpo.editais ?? "3", 10) || 3, 1), 10);
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(alvo)) return json({ ok: false, motivo: "E-mail inválido." }, 400, origin);

      let usuario = (await todosUsuarios()).find((x) => (x.email ?? "").toLowerCase() === alvo);
      let criado = false;
      if (!usuario) {
        const { data, error } = await admin.auth.admin.createUser({ email: alvo, email_confirm: true });
        if (error) throw error;
        usuario = { id: data.user.id, email: alvo, created_at: data.user.created_at };
        criado = true;
      }
      const { error } = await admin.from("acessos").upsert({
        user_id: usuario.id, plano: "beta", editais_max: editais, artigos_max: 40,
        valido_ate: new Date(Date.now() + dias * 864e5).toISOString(),
      });
      if (error) throw error;
      return json({ ok: true, mensagem: `Passe Beta liberado para ${alvo} por ${dias} dias (${editais} editais).` + (criado ? " Conta criada: a pessoa entra pela Área do Projeto com esse e-mail." : "") }, 200, origin);
    }

    if (acao === "revogar") {
      const alvo = String(corpo.email ?? "").trim().toLowerCase();
      const usuario = (await todosUsuarios()).find((x) => (x.email ?? "").toLowerCase() === alvo);
      if (!usuario) return json({ ok: false, motivo: "Usuário não encontrado." }, 404, origin);
      if (ADMINS.includes(alvo)) return json({ ok: false, motivo: "Não é possível revogar o passe do administrador por aqui." }, 400, origin);
      const { error } = await admin.from("acessos").delete().eq("user_id", usuario.id);
      if (error) throw error;
      return json({ ok: true, mensagem: `Passe de ${alvo} revogado.` }, 200, origin);
    }

    return json({ ok: false, motivo: "Ação desconhecida." }, 400, origin);
  } catch (e) {
    console.error("admin", e);
    return json({ ok: false, motivo: "Erro interno: " + (e instanceof Error ? e.message : String(e)) }, 500, origin);
  }
});
