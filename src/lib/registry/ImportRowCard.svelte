<script lang="ts">
    import { supabaseBrowser } from '$lib/supabase-browser';
    import { STATUS_LABEL, IMPORT_FIELD_LABEL, type ImportRow, type ImportCandidate, type PersonRow } from '$lib/registry';

    let {
        row, busy, decide
    }: {
        row: ImportRow;
        busy: boolean;
        decide: (row: ImportRow, decision: 'link' | 'new' | 'skip' | null, personId?: string) => void;
    } = $props();

    const d = $derived(row.data);
    const KIND: Record<string, { text: string; style: string }> = {
        strong: { text: '이름·생일/전화 일치', style: 'bg-primary-50 text-primary-800' },
        name: { text: '이름만 같음', style: 'bg-amber-50 text-amber-700' },
        phone: { text: '전화만 같음', style: 'bg-amber-50 text-amber-700' },
        search: { text: '직접 찾음', style: 'bg-gray-100 text-gray-600' }
    };

    // 직접 찾은 사람은 후보 목록 뒤에 붙인다
    let found = $state<ImportCandidate[]>([]);
    const choices = $derived([...row.candidates, ...found.filter((f) => !row.candidates.some((c) => c.person_id === f.person_id))]);
    let picked = $state<string | null>(null);
    $effect(() => {
        if (picked === null && row.suggestion === 'link' && row.candidates[0]) picked = row.candidates[0].person_id;
    });

    let q = $state('');
    let searching = $state(false);
    let searchMsg = $state('');
    async function search(e: SubmitEvent) {
        e.preventDefault();
        if (!q.trim()) return;
        searching = true;
        const { data, error } = await supabaseBrowser.rpc('registry_search', { p_filters: { q: q.trim() }, p_limit: 10, p_offset: 0 });
        searching = false;
        if (error) {
            searchMsg = '찾지 못했습니다.';
            return;
        }
        const got = (data ?? []) as PersonRow[];
        searchMsg = got.length ? '' : '교적에서 찾지 못했습니다.';
        found = got.map((p) => ({
            person_id: p.person_id, kind: 'search', name: p.name, gender: p.gender, birth_date: p.birth_date, phone: p.phone,
            office: p.office, has_account: p.has_account, in_registry: true, status: p.status, group_name: p.group_name
        }));
    }

    const digits = (s: string | null | undefined) => (s ?? '').replace(/\D/g, '');
    const differs = (a: string | null | undefined, b: string | null | undefined) => !!a && !!b && a !== b;
</script>

<div class="rounded-2xl border {row.sheet === 'deceased' ? 'border-red-200' : 'border-gray-200'} p-4">
    <div class="grid md:grid-cols-2 gap-4">
        <!-- 디모데 -->
        <div class="text-sm">
            <div class="flex flex-wrap items-center gap-2 mb-1.5">
                <span class="text-xs font-bold text-gray-400">디모데</span>
                <b class="text-gray-900 text-base">{d.name}</b>
                <span class="text-gray-500">{d.gender ?? ''} {d.birth_date ?? d.birth_year ?? ''}{d.birth_lunar ? ' (음)' : ''}</span>
                {#if row.sheet === 'deceased'}
                    <span class="px-2 py-0.5 rounded-full text-xs font-bold bg-red-50 text-red-600">별세자 명단{d.deceased_on ? ` · ${d.deceased_on}` : ''}</span>
                {/if}
                {#if row.has_memo}<span class="px-2 py-0.5 rounded-full text-xs bg-gray-100 text-gray-500">메모 있음 · 교역자만</span>{/if}
            </div>
            <dl class="grid grid-cols-[4.5rem_1fr] gap-x-2 gap-y-0.5 text-gray-600">
                {#if d.mobile || d.home_phone}<dt class="text-gray-400">전화</dt><dd>{[d.mobile, d.home_phone].filter(Boolean).join(' · ')}</dd>{/if}
                {#if d.status || d.kind}<dt class="text-gray-400">상태</dt><dd>{[d.status, d.kind, d.kind_detail].filter(Boolean).join(' · ')}</dd>{/if}
                {#if d.district || d.zone}<dt class="text-gray-400">교구·구역</dt><dd>{[d.district, d.zone].filter(Boolean).join(' · ')}</dd>{/if}
                {#if d.office || d.office_detail}<dt class="text-gray-400">직분</dt><dd>{d.office_detail ?? d.office}{d.office_started_on ? ` (${d.office_started_on})` : ''}</dd>{/if}
                {#if d.head_name}<dt class="text-gray-400">세대</dt><dd>세대주 {d.head_name}{d.relation ? ` · ${d.relation}` : ''}</dd>{/if}
                {#if d.registered_on}<dt class="text-gray-400">등록일</dt><dd>{d.registered_on}</dd>{/if}
                {#if d.baptism}<dt class="text-gray-400">세례</dt><dd>{d.baptism}{d.baptism_date ? ` (${d.baptism_date})` : ''}</dd>{/if}
                {#if d.school}<dt class="text-gray-400">교회학교</dt><dd>{d.school}</dd>{/if}
            </dl>
        </div>

        <!-- 지금 사람 -->
        <div class="text-sm">
            {#if row.applied_at}
                <div class="mb-2">
                    <a href={`/registry/${row.person_id}`} class="font-bold text-primary-800 hover:underline">{row.person_name ?? '교적 카드'} →</a>
                    {#if row.result?.created}<span class="ml-2 px-2 py-0.5 rounded-full text-xs font-bold bg-primary-50 text-primary-800">새 교적</span>{/if}
                </div>
                {#if row.result?.filled?.length}
                    <div class="flex flex-wrap gap-1 mb-2">
                        {#each row.result.filled.filter((f) => f !== 'created') as f}
                            <span class="px-2 py-0.5 rounded-full text-xs bg-gray-100 text-gray-600">{IMPORT_FIELD_LABEL[f] ?? f}</span>
                        {/each}
                    </div>
                {/if}
                {#if row.result?.diffs?.length}
                    <p class="text-xs font-bold text-amber-700 mb-1">디모데와 다른 값 (바꾸지 않았습니다)</p>
                    <ul class="space-y-0.5 text-xs text-gray-600">
                        {#each row.result.diffs as x}
                            <li><b>{IMPORT_FIELD_LABEL[x.field] ?? x.field}</b> — 디모데 {x.dimode ?? '(없음)'} / 지금 {x.current ?? '(없음)'}</li>
                        {/each}
                    </ul>
                {/if}
            {:else}
                {#if choices.length === 0}
                    <p class="text-gray-400 mb-2">지금 교적·프로필에서 같은 사람을 찾지 못했습니다.</p>
                {/if}
                <div class="space-y-1.5">
                    {#each choices as c (c.person_id)}
                        <label class="flex items-start gap-2 rounded-xl border px-3 py-2 cursor-pointer
                            {picked === c.person_id ? 'border-primary-500 bg-primary-50/50' : 'border-gray-100 hover:border-gray-300'}
                            {row.decision === 'link' && row.person_id === c.person_id ? 'ring-2 ring-primary-300' : ''}">
                            <input type="radio" class="mt-1" name={`pick-${row.id}`} value={c.person_id} bind:group={picked} disabled={!!row.decision} />
                            <span class="flex-1">
                                <span class="flex flex-wrap items-center gap-1.5">
                                    <b class="text-gray-900">{c.name}</b>
                                    <span class="px-1.5 py-0.5 rounded text-[11px] font-bold {KIND[c.kind]?.style ?? ''}">{KIND[c.kind]?.text ?? c.kind}</span>
                                    {#if c.has_account}<span class="text-xs text-blue-600">앱 가입</span>{/if}
                                    <span class="text-xs {c.in_registry ? 'text-gray-500' : 'text-amber-700'}">
                                        {c.in_registry ? (STATUS_LABEL[c.status ?? ''] ?? '교적') : '교적 없음 (연결하면 교적에 올림)'}
                                    </span>
                                </span>
                                <span class="block text-xs text-gray-500 mt-0.5">
                                    {c.gender ?? ''}
                                    <span class={differs(c.birth_date, d.birth_date) ? 'text-red-600 font-bold' : ''}>{c.birth_date ?? '생일 없음'}</span>
                                    · <span class={differs(digits(c.phone), digits(d.mobile)) ? 'text-red-600 font-bold' : ''}>{c.phone ?? '전화 없음'}</span>
                                    {c.office ? ` · ${c.office}` : ''}{c.group_name ? ` · ${c.group_name}` : ''}
                                </span>
                            </span>
                        </label>
                    {/each}
                </div>
                {#if !row.decision}
                    <form onsubmit={search} class="flex gap-1.5 mt-2">
                        <input bind:value={q} placeholder="교적에서 직접 찾기 (이름·전화)"
                            class="flex-1 px-3 py-1.5 rounded-lg border border-gray-200 text-xs focus:outline-none focus:border-primary-500" />
                        <button type="submit" disabled={searching} class="px-3 py-1.5 rounded-lg border border-gray-200 text-xs font-bold text-gray-600 hover:bg-gray-50">찾기</button>
                    </form>
                    {#if searchMsg}<p class="text-xs text-gray-400 mt-1">{searchMsg}</p>{/if}
                {/if}
            {/if}
        </div>
    </div>

    {#if !row.applied_at}
        <div class="flex flex-wrap items-center gap-2 mt-3 pt-3 border-t border-gray-50">
            {#if row.decision}
                <span class="text-sm font-bold text-gray-700">
                    {row.decision === 'link' ? `${row.person_name ?? ''}님과 연결` : row.decision === 'new' ? '새 교적으로 만듦' : '가져오지 않음'}
                </span>
                <button type="button" disabled={busy} onclick={() => decide(row, null)}
                    class="ml-auto px-3 py-1.5 rounded-lg text-xs font-bold border border-gray-200 text-gray-600 hover:bg-gray-50 disabled:opacity-50">되돌리기</button>
            {:else}
                <button type="button" disabled={busy || !picked} onclick={() => picked && decide(row, 'link', picked)}
                    class="px-3 py-1.5 rounded-lg text-xs font-bold bg-primary-900 text-white disabled:opacity-40">고른 사람과 같은 사람</button>
                {#if row.sheet !== 'deceased'}
                    <button type="button" disabled={busy} onclick={() => decide(row, 'new')}
                        class="px-3 py-1.5 rounded-lg text-xs font-bold border border-primary-200 text-primary-800 hover:bg-primary-50 disabled:opacity-50">새 교적으로</button>
                {/if}
                <button type="button" disabled={busy} onclick={() => decide(row, 'skip')}
                    class="ml-auto px-3 py-1.5 rounded-lg text-xs font-bold border border-gray-200 text-gray-500 hover:bg-gray-50 disabled:opacity-50">가져오지 않음</button>
            {/if}
        </div>
    {/if}
</div>
