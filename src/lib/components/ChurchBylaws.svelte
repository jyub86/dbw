<script lang="ts">
    import { onMount } from "svelte";
    import { supabaseBrowser } from "$lib/supabase-browser";

    /**
     * 교회운영세칙. 본문은 public.church_documents(slug = 'bylaws')에 있고,
     * 교인 인증된 사람과 관리자만 읽을 수 있다(RLS). 그 밖의 사람에게는 안내만 보인다.
     */
    type Article = { no: number; title: string; paras: string[] };
    type Chapter = { no: number; title: string; articles: Article[] };
    type Part = { no: number; title: string; chapters: Chapter[] };
    type Appendix = {
        title: string;
        kind: "rules" | "guide";
        chapters?: Chapter[];
        sections?: { title: string; items: string[] }[];
    };
    type Doc = {
        title: string;
        revision: string | null;
        effective_on: string | null;
        source: string | null;
        body: { preamble: string[]; parts: Part[]; closing: string | null; appendices: Appendix[] };
    };

    let phase = $state<"loading" | "login" | "denied" | "ready" | "error">("loading");
    let doc = $state<Doc | null>(null);
    let q = $state("");
    let tocOpen = $state(false);

    onMount(async () => {
        const {
            data: { session },
        } = await supabaseBrowser.auth.getSession();
        if (!session) {
            phase = "login";
            return;
        }
        const { data, error } = await supabaseBrowser
            .from("church_documents")
            .select("title, revision, effective_on, source, body")
            .eq("slug", "bylaws")
            .maybeSingle();
        if (error) {
            phase = "error";
            return;
        }
        if (!data) {
            phase = "denied"; // 교인 인증 전이면 정책 때문에 행이 오지 않는다
            return;
        }
        doc = data as Doc;
        phase = "ready";
    });

    const term = $derived(q.trim());
    const hit = (a: Article) => !term || a.title.includes(term) || a.paras.some((p) => p.includes(term));
    const parts = $derived(
        (doc?.body.parts ?? [])
            .map((p) => ({
                ...p,
                chapters: p.chapters
                    .map((c) => ({ ...c, articles: c.articles.filter(hit) }))
                    .filter((c) => c.articles.length > 0),
            }))
            .filter((p) => p.chapters.length > 0),
    );
    const hitCount = $derived(parts.reduce((n, p) => n + p.chapters.reduce((m, c) => m + c.articles.length, 0), 0));

    // 검색어를 표시한다
    function segs(text: string): { t: string; m: boolean }[] {
        if (!term) return [{ t: text, m: false }];
        const out: { t: string; m: boolean }[] = [];
        let i = 0;
        for (;;) {
            const j = text.indexOf(term, i);
            if (j < 0) break;
            if (j > i) out.push({ t: text.slice(i, j), m: false });
            out.push({ t: term, m: true });
            i = j + term.length;
        }
        if (i < text.length) out.push({ t: text.slice(i), m: false });
        return out;
    }

    // 항목 들여쓰기: ① 같은 원문자는 한 단계 더 들어간다
    function paraClass(p: string) {
        if (/^[①-⑳]/.test(p)) return "pl-10 -indent-5";
        if (/^(\d+\.|[가-하]\.|\(\d+\))\s?/.test(p)) return "pl-5 -indent-5";
        return "";
    }

    function fmtDate(d: string | null) {
        if (!d) return "";
        const [y, m, day] = d.split("-").map(Number);
        return `${y}년 ${m}월 ${day}일`;
    }
</script>

{#snippet text(s: string)}{#each segs(s) as g}{#if g.m}<mark class="bg-amber-200 rounded px-0.5">{g.t}</mark>{:else}{g.t}{/if}{/each}{/snippet}

{#snippet articleView(a: Article, prefix: string)}
    <article id={`${prefix}${a.no}`} class="scroll-mt-28 py-5 border-b border-gray-100 last:border-0">
        <h5 class="text-lg font-bold text-gray-900 mb-2">
            제{a.no}조 <span class="text-primary-700">({@render text(a.title)})</span>
        </h5>
        <div class="space-y-1.5 text-base md:text-lg text-gray-700 leading-relaxed break-keep">
            {#each a.paras as p}
                <p class={paraClass(p)}>{@render text(p)}</p>
            {/each}
        </div>
    </article>
{/snippet}

<div class="text-center mb-14">
    <span class="text-primary-600 font-bold tracking-widest uppercase mb-4 block">Church Bylaws</span>
    <h2 class="text-4xl md:text-5xl font-black text-gray-900 font-serif mb-6">교회운영세칙</h2>
    <p class="text-xl text-gray-600 max-w-2xl mx-auto break-keep">
        부평동부교회를 질서 있게 섬기기 위해 당회의 발의와 공동의회의 의결로 정한 운영 규칙입니다.
    </p>
</div>

{#if phase === "loading"}
    <div class="py-24 text-center text-gray-400">불러오는 중…</div>
{:else if phase === "login" || phase === "denied"}
    <div class="max-w-xl mx-auto rounded-3xl border border-gray-200 bg-gray-50 px-8 py-12 text-center">
        <p class="text-xl font-bold text-gray-900 mb-3">교인만 볼 수 있습니다</p>
        {#if phase === "login"}
            <p class="text-gray-600 mb-6 break-keep">교회운영세칙은 교인 인증을 받은 분께 공개합니다. 로그인해 주세요.</p>
            <a href="/login" class="inline-block px-6 py-3 rounded-2xl bg-primary-900 text-white font-bold hover:bg-primary-800">로그인</a>
        {:else}
            <p class="text-gray-600 break-keep">
                교인 인증을 받은 분께 공개합니다. 아직 인증 전이라면 교회 사무실이나 담당자에게 문의해 주세요.
            </p>
        {/if}
    </div>
{:else if phase === "error"}
    <div class="py-24 text-center text-red-500">교회운영세칙을 불러오지 못했습니다. 잠시 뒤 다시 시도해 주세요.</div>
{:else if doc}
    <div class="lg:grid lg:grid-cols-[16rem_1fr] lg:gap-12">
        <!-- 목차 -->
        <aside class="mb-8 lg:mb-0">
            <div class="lg:sticky lg:top-28 space-y-4">
                <div class="rounded-2xl bg-primary-50 px-5 py-4 text-sm text-gray-700">
                    <p class="font-bold text-primary-900">{doc.title}</p>
                    <p class="mt-1">
                        {[doc.revision, doc.effective_on ? `${fmtDate(doc.effective_on)} 시행` : null].filter(Boolean).join(" · ")}
                    </p>
                    {#if doc.source}<p class="mt-1 text-gray-500">출처: {doc.source}</p>{/if}
                    <p class="mt-2 inline-block px-2 py-0.5 rounded-full bg-white text-xs font-bold text-primary-700">교인 전용</p>
                </div>
                <input
                    type="search"
                    bind:value={q}
                    placeholder="조문 찾기 (예: 정년, 권사)"
                    class="w-full px-4 py-3 rounded-2xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white"
                />
                {#if term}
                    <p class="text-sm text-gray-500 px-1">{hitCount}개 조문</p>
                {/if}
                <button
                    type="button"
                    class="lg:hidden w-full px-4 py-3 rounded-2xl border border-gray-200 font-bold text-gray-700 text-left"
                    onclick={() => (tocOpen = !tocOpen)}
                >
                    목차 {tocOpen ? "접기" : "펼치기"}
                </button>
                <nav class="{tocOpen ? '' : 'hidden'} lg:block text-sm max-h-[60vh] overflow-y-auto pr-1">
                    {#each doc.body.parts as p}
                        <p class="font-bold text-gray-900 mt-3 first:mt-0">제{p.no}편 {p.title}</p>
                        <ul class="mt-1 space-y-0.5">
                            {#each p.chapters as c}
                                <li>
                                    <a
                                        href={`#art-${c.articles[0]?.no}`}
                                        class="block px-2 py-1 rounded-lg text-gray-600 hover:bg-gray-100 hover:text-primary-700"
                                        onclick={() => (tocOpen = false)}
                                    >
                                        제{c.no}장 {c.title}
                                    </a>
                                </li>
                            {/each}
                        </ul>
                    {/each}
                    {#if doc.body.appendices.length}
                        <p class="font-bold text-gray-900 mt-3">별첨</p>
                        <ul class="mt-1 space-y-0.5">
                            {#each doc.body.appendices as ap, i}
                                <li>
                                    <a href={`#appendix-${i}`} class="block px-2 py-1 rounded-lg text-gray-600 hover:bg-gray-100 hover:text-primary-700" onclick={() => (tocOpen = false)}>
                                        {ap.title}
                                    </a>
                                </li>
                            {/each}
                        </ul>
                    {/if}
                </nav>
            </div>
        </aside>

        <!-- 본문 -->
        <div class="min-w-0">
            {#if !term && doc.body.preamble.length}
                <section class="mb-12 rounded-3xl border border-gray-100 bg-white px-6 md:px-10 py-8">
                    <h3 class="text-2xl font-black text-gray-900 mb-4">전문</h3>
                    {#each doc.body.preamble as p}
                        <p class="text-base md:text-lg text-gray-700 leading-relaxed break-keep">{p}</p>
                    {/each}
                </section>
            {/if}

            {#if term && hitCount === 0}
                <p class="py-16 text-center text-gray-400">'{term}'이(가) 들어간 조문이 없습니다.</p>
            {/if}

            {#each parts as p}
                <section class="mb-14">
                    <h3 class="text-2xl md:text-3xl font-black text-primary-700 mb-6 pb-3 flex items-center gap-3 border-b-2 border-primary-100">
                        <span class="w-2.5 h-8 bg-primary-600 rounded-full inline-block"></span>
                        제{p.no}편 {p.title}
                    </h3>
                    {#each p.chapters as c}
                        <div class="mb-8">
                            <h4 class="text-xl font-black text-gray-900 mb-1">제{c.no}장 {c.title}</h4>
                            <div class="pl-0 md:pl-4">
                                {#each c.articles as a (a.no)}
                                    {@render articleView(a, "art-")}
                                {/each}
                            </div>
                        </div>
                    {/each}
                </section>
            {/each}

            {#if !term && doc.body.closing}
                <p class="text-right text-gray-500 mb-16">{doc.body.closing}</p>
            {/if}

            {#if !term}
                {#each doc.body.appendices as ap, i}
                    <section id={`appendix-${i}`} class="scroll-mt-28 mb-14 rounded-3xl border border-gray-100 bg-gray-50/60 px-6 md:px-10 py-8">
                        <p class="text-sm font-bold text-primary-600 mb-1">별첨</p>
                        <h3 class="text-2xl font-black text-gray-900 mb-6">{ap.title}</h3>
                        {#if ap.kind === "rules"}
                            {#each ap.chapters ?? [] as c}
                                <h4 class="text-lg font-black text-gray-900 mt-6 first:mt-0">제{c.no}장 {c.title}</h4>
                                {#each c.articles as a}
                                    {@render articleView(a, `appendix-${i}-art-`)}
                                {/each}
                            {/each}
                        {:else}
                            {#each ap.sections ?? [] as s}
                                <h4 class="text-lg font-black text-gray-900 mt-6 first:mt-0 mb-2">{s.title}</h4>
                                <ol class="list-decimal pl-6 space-y-1 text-base md:text-lg text-gray-700 leading-relaxed break-keep">
                                    {#each s.items as it}<li>{it}</li>{/each}
                                </ol>
                            {/each}
                        {/if}
                    </section>
                {/each}
            {/if}
        </div>
    </div>
{/if}
