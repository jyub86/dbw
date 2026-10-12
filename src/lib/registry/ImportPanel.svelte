<script lang="ts">
    import { onMount } from 'svelte';
    import { call, fmtDateTime, IMPORT_FIELD_LABEL, type ImportRow, type ImportSummary, type RegistryMe } from '$lib/registry';
    import ImportRowCard from './ImportRowCard.svelte';

    let { me }: { me: RegistryMe } = $props();

    type View = 'link' | 'review' | 'new' | 'decided' | 'skipped' | 'applied' | 'diffs';
    type Stats = { rows: number; created: number; filled: Record<string, number>; diffs: Record<string, number>; remaining?: number };

    const VIEWS: { key: View; name: string; count: (s: ImportSummary) => number; help: string }[] = [
        { key: 'link', name: '연결 제안', count: (s) => s.link,
          help: '이름과 생년월일(또는 전화)이 지금 한 사람과만 맞는 행입니다. 훑어보고 이상한 행만 고친 뒤 한꺼번에 확정하세요.' },
        { key: 'review', name: '확인 필요', count: (s) => s.review,
          help: '이름만 같거나, 같은 이름이 여럿이거나, 별세자 명단과 맞는 행입니다. 한 명씩 같은 사람인지 확인해 주세요.' },
        { key: 'new', name: '새 교적 후보', count: (s) => s.new,
          help: '디모데에서는 출석 중인데 지금 교적·프로필에 없는 분입니다. 실제로 출석하는 분이면 새 교적으로 만드세요.' },
        { key: 'decided', name: '확정 (반영 전)', count: (s) => s.decided, help: '반영하기를 누르면 이 행들이 교적에 들어갑니다.' },
        { key: 'skipped', name: '가져오지 않음', count: (s) => s.skipped, help: '가져오지 않기로 한 행입니다.' },
        { key: 'applied', name: '반영됨', count: (s) => s.applied, help: '교적에 반영한 행입니다. 고칠 것은 교적 카드에서 고치세요.' },
        { key: 'diffs', name: '차이', count: (s) => s.diffs,
          help: '반영할 때 지금 값과 디모데 값이 달라서 바꾸지 않은 항목입니다. 교적 카드에서 맞는 값으로 고쳐 주세요.' }
    ];
    const PAGE = 100;

    let summary = $state<ImportSummary | null>(null);
    let view = $state<View>('link');
    let rows = $state<ImportRow[]>([]);
    let total = $state(0);
    let loading = $state(true);
    let busy = $state(false);
    let msg = $state('');
    let errorMsg = $state('');

    function notify(text: string, isError = false) {
        if (isError) { errorMsg = text; msg = ''; } else { msg = text; errorMsg = ''; }
    }

    async function loadSummary() {
        const r = await call<ImportSummary>('registry_import_summary', {}, '현황을 불러오지 못했습니다.');
        if (r.ok) summary = r.data;
        else notify(r.error, true);
    }

    let seq = 0;
    async function loadRows(reset = true) {
        const mine = ++seq;
        loading = true;
        const r = await call<ImportRow[]>('registry_import_list', { p_view: view, p_limit: PAGE, p_offset: reset ? 0 : rows.length },
            '목록을 불러오지 못했습니다.');
        if (mine !== seq) return;
        loading = false;
        if (!r.ok) return notify(r.error, true);
        rows = reset ? r.data : [...rows, ...r.data];
        total = r.data[0]?.total ?? (reset ? 0 : total);
    }

    async function refresh() {
        await Promise.all([loadSummary(), loadRows(true)]);
    }

    function show(v: View) {
        view = v;
        loadRows(true);
    }

    // ─── 올리기 (관리자) ───
    let uploadDone = $state(0);
    let uploadTotal = $state(0);
    async function upload(e: Event) {
        const input = e.currentTarget as HTMLInputElement;
        const file = input.files?.[0];
        input.value = '';
        if (!file) return;
        let parsed: { source?: string; rows?: unknown[] };
        try {
            parsed = JSON.parse(await file.text());
        } catch {
            return notify('파일을 읽지 못했습니다. 정리본에서 만든 디모데_가져오기.json 파일을 골라 주세요.', true);
        }
        if (parsed?.source !== 'dimode' || !Array.isArray(parsed.rows) || parsed.rows.length === 0) {
            return notify('디모데 가져오기 파일이 아닙니다.', true);
        }
        busy = true;
        uploadTotal = parsed.rows.length;
        uploadDone = 0;
        for (let i = 0; i < parsed.rows.length; i += 150) {
            const chunk = parsed.rows.slice(i, i + 150);
            const r = await call<number>('registry_import_load', { p_rows: chunk }, '올리지 못했습니다.');
            if (!r.ok) {
                busy = false;
                return notify(`${uploadDone}행까지 올리고 멈췄습니다: ${r.error}`, true);
            }
            uploadDone += chunk.length;
        }
        busy = false;
        notify(`${uploadTotal}행을 올리고 지금 교적과 대조했습니다.`);
        view = 'link';
        await refresh();
    }

    // ─── 정하기 ───
    async function decide(row: ImportRow, decision: 'link' | 'new' | 'skip' | null, personId?: string) {
        busy = true;
        const r = await call('registry_import_decide', { p_row_id: row.id, p_decision: decision, p_person_id: personId ?? null },
            '처리하지 못했습니다.');
        busy = false;
        if (!r.ok) return notify(r.error, true);
        notify(decision === null ? `${row.data.name} 행을 되돌렸습니다.` : `${row.data.name} 행을 정했습니다.`);
        // 정한 행은 지금 목록에서 빠진다 (확정·제외 목록에서 되돌리면 원래 목록으로 돌아간다)
        rows = rows.filter((x) => x.id !== row.id);
        total = Math.max(0, total - 1);
        await loadSummary();
    }

    let acceptArmed = $state(false);
    async function acceptAll() {
        if (!acceptArmed) return (acceptArmed = true);
        acceptArmed = false;
        busy = true;
        const r = await call<number>('registry_import_accept', {}, '확정하지 못했습니다.');
        busy = false;
        if (!r.ok) return notify(r.error, true);
        notify(`연결 제안 ${r.data}건을 확정했습니다. 반영하기 전까지는 '확정' 목록에서 되돌릴 수 있습니다.`);
        await refresh();
    }

    // ─── 미리보기·반영 ───
    let preview = $state<Stats | null>(null);
    async function runPreview() {
        busy = true;
        const r = await call<Stats>('registry_import_apply', { p_dry_run: true }, '미리보기를 하지 못했습니다.');
        busy = false;
        if (!r.ok) return notify(r.error, true);
        preview = r.data;
    }

    let applyArmed = $state(false);
    let applied = $state(0);
    async function applyAll() {
        if (!applyArmed) return (applyArmed = true);
        applyArmed = false;
        busy = true;
        applied = 0;
        let created = 0;
        for (;;) {
            const r = await call<Stats>('registry_import_apply', { p_limit: 150 }, '반영하지 못했습니다.');
            if (!r.ok) {
                busy = false;
                await refresh();
                return notify(`${applied}행까지 반영하고 멈췄습니다: ${r.error}`, true);
            }
            applied += r.data.rows;
            created += r.data.created;
            if (!r.data.remaining || r.data.rows === 0) break;
        }
        busy = false;
        preview = null;
        notify(`${applied}행을 반영했습니다 (새 교적 ${created}명). '차이' 목록에서 디모데와 다른 값을 확인해 주세요.`);
        view = 'diffs';
        await refresh();
    }

    // ─── 정리 (관리자) ───
    let closeArmed = $state(false);
    async function closeImport() {
        if (!closeArmed) return (closeArmed = true);
        closeArmed = false;
        busy = true;
        const r = await call<number>('registry_import_close', {}, '정리하지 못했습니다.');
        busy = false;
        if (!r.ok) return notify(r.error, true);
        notify(`올린 행 ${r.data}개를 지웠습니다. 반영한 교적과 디모데 메모는 남아 있습니다.`);
        await refresh();
    }

    const statLine = (o: Record<string, number>) =>
        Object.entries(o).filter(([k]) => k !== 'created').map(([k, v]) => `${IMPORT_FIELD_LABEL[k] ?? k} ${v}`).join(' · ') || '없음';

    onMount(refresh);
</script>

{#if msg}<div class="mb-5 bg-primary-50 border border-primary-100 text-primary-800 text-sm rounded-xl px-4 py-3">{msg}</div>{/if}
{#if errorMsg}<div class="mb-5 bg-red-50 border border-red-100 text-red-600 text-sm rounded-xl px-4 py-3">{errorMsg}</div>{/if}

<div class="text-sm text-gray-500 mb-6 space-y-1">
    <p>디모데 정리본을 지금 교적과 맞춰 봅니다. 같은 사람으로 확정한 행만 <b class="text-gray-700">비어 있는 칸</b>을 채우고(등록일·세례·임직일·주소·세대 등), 이미 있는 값은 바꾸지 않습니다.</p>
    <p>디모데 메모는 교역자(심방 권한)만 교적 카드에서 볼 수 있습니다. 교회를 떠난 과거 교인은 파일에 넣지 않았습니다.</p>
</div>

{#if me.is_admin}
    <section class="mb-8 rounded-2xl border border-gray-100 bg-gray-50 px-4 py-4">
        <h2 class="text-sm font-black text-gray-900 mb-1">1. 파일 올리기 <span class="text-xs font-bold text-gray-400">(사이트 관리자)</span></h2>
        <p class="text-xs text-gray-500 mb-3">
            정리본에서 만든 <b>디모데_가져오기.json</b>을 고르세요. 같은 파일을 다시 올려도 됩니다(반영 전 행만 새 값으로 바뀝니다).
            {#if summary?.uploaded_at}마지막으로 올린 때: {fmtDateTime(summary.uploaded_at)}{/if}
        </p>
        <label class="inline-flex items-center px-4 py-2 rounded-xl bg-gray-900 text-white font-bold text-sm cursor-pointer hover:bg-gray-700 {busy ? 'opacity-50 pointer-events-none' : ''}">
            파일 고르기
            <input type="file" accept=".json,application/json" class="hidden" onchange={upload} disabled={busy} />
        </label>
        {#if uploadTotal && uploadDone < uploadTotal}<span class="ml-3 text-sm text-gray-500">올리는 중 {uploadDone}/{uploadTotal}</span>{/if}
    </section>
{/if}

{#if summary && summary.total === 0}
    <div class="py-16 text-center text-gray-400 text-sm">
        올린 디모데 자료가 없습니다.{me.is_admin ? '' : ' 사이트 관리자가 파일을 올리면 여기서 대조할 수 있습니다.'}
    </div>
{:else if summary}
    <!-- 반영 -->
    {#if summary.decided > 0}
        <section class="mb-8 rounded-2xl border border-primary-100 bg-primary-50/40 px-4 py-4">
            <h2 class="text-sm font-black text-gray-900 mb-1">3. 반영하기 <span class="text-primary-700">{summary.decided}행 확정</span></h2>
            <p class="text-xs text-gray-500 mb-3">미리보기는 실제로 바꾸지 않고 결과만 셉니다. 반영한 뒤에는 이 화면에서 되돌릴 수 없고, 교적 카드에서 고쳐야 합니다.</p>
            <div class="flex flex-wrap gap-2">
                <button type="button" onclick={runPreview} disabled={busy}
                    class="px-4 py-2 rounded-xl border border-primary-200 bg-white text-primary-800 font-bold text-sm hover:bg-primary-50 disabled:opacity-50">미리보기</button>
                <button type="button" onclick={applyAll} disabled={busy}
                    class="px-4 py-2 rounded-xl font-bold text-sm text-white disabled:opacity-50 {applyArmed ? 'bg-red-600' : 'bg-primary-900'}">
                    {applyArmed ? `정말 ${summary.decided}행을 반영합니다` : '반영하기'}
                </button>
                {#if applyArmed}
                    <button type="button" onclick={() => (applyArmed = false)} class="px-3 py-2 text-sm text-gray-500">취소</button>
                {/if}
                {#if busy && applied}<span class="self-center text-sm text-gray-500">반영 중 {applied}행…</span>{/if}
            </div>
            {#if preview}
                <div class="mt-3 text-sm text-gray-700 space-y-0.5">
                    <p><b>{preview.rows}</b>행 반영 · 새 교적 <b>{preview.created}</b>명</p>
                    <p class="text-xs">채울 항목: {statLine(preview.filled)}</p>
                    <p class="text-xs text-amber-700">바꾸지 않고 차이로 남길 항목: {statLine(preview.diffs)}</p>
                </div>
            {/if}
        </section>
    {/if}

    <h2 class="text-sm font-black text-gray-900 mb-2">2. 같은 사람 확인</h2>
    <div class="flex flex-wrap gap-1 mb-4 bg-gray-100 rounded-2xl p-1 w-fit">
        {#each VIEWS as v}
            <button type="button" onclick={() => show(v.key)}
                class="px-3 py-1.5 rounded-xl text-sm font-bold transition-colors {view === v.key ? 'bg-white text-primary-800 shadow-sm' : 'text-gray-500 hover:text-gray-800'}">
                {v.name} <span class="text-xs {view === v.key ? 'text-primary-600' : 'text-gray-400'}">{v.count(summary)}</span>
            </button>
        {/each}
    </div>
    <div class="flex flex-wrap items-center gap-3 mb-4">
        <p class="text-xs text-gray-500 flex-1 min-w-[16rem]">{VIEWS.find((v) => v.key === view)?.help}</p>
        {#if view === 'link' && summary.link > 0}
            <button type="button" onclick={acceptAll} disabled={busy}
                class="px-4 py-2 rounded-xl font-bold text-sm text-white disabled:opacity-50 {acceptArmed ? 'bg-red-600' : 'bg-primary-900'}">
                {acceptArmed ? `정말 ${summary.link}건을 확정합니다` : `연결 제안 ${summary.link}건 모두 확정`}
            </button>
            {#if acceptArmed}<button type="button" onclick={() => (acceptArmed = false)} class="text-sm text-gray-500">취소</button>{/if}
        {/if}
    </div>

    {#if loading && rows.length === 0}
        <div class="py-16 text-center text-gray-400 text-sm">불러오는 중…</div>
    {:else if rows.length === 0}
        <div class="py-16 text-center text-gray-400 text-sm">이 목록에 남은 행이 없습니다.</div>
    {:else}
        <div class="space-y-3">
            {#each rows as row (row.id)}
                <ImportRowCard {row} {busy} {decide} />
            {/each}
        </div>
        {#if rows.length < total}
            <div class="text-center mt-4">
                <button type="button" onclick={() => loadRows(false)} disabled={loading}
                    class="px-5 py-2 rounded-xl border border-gray-200 text-sm font-bold text-gray-600 hover:bg-gray-50 disabled:opacity-50">
                    더 보기 ({rows.length}/{total})
                </button>
            </div>
        {/if}
    {/if}

    {#if me.is_admin && summary.decided === 0}
        <section class="mt-12 rounded-2xl border border-red-100 px-4 py-4">
            <h2 class="text-sm font-black text-gray-900 mb-1">4. 가져오기 정리 <span class="text-xs font-bold text-gray-400">(사이트 관리자)</span></h2>
            <p class="text-xs text-gray-500 mb-3">
                대조가 끝나면 올린 디모데 행을 지웁니다. 반영한 교적, 디모데 메모, 디모데 ID·헌금번호는 남습니다.
                아직 정하지 않은 행({summary.link + summary.review + summary.new}행)도 함께 지워집니다.
            </p>
            <button type="button" onclick={closeImport} disabled={busy}
                class="px-4 py-2 rounded-xl font-bold text-sm disabled:opacity-50 {closeArmed ? 'bg-red-600 text-white' : 'border border-red-200 text-red-600 hover:bg-red-50'}">
                {closeArmed ? `정말 올린 행 ${summary.total}개를 지웁니다` : '올린 행 지우기'}
            </button>
            {#if closeArmed}<button type="button" onclick={() => (closeArmed = false)} class="ml-2 text-sm text-gray-500">취소</button>{/if}
        </section>
    {/if}
{/if}
