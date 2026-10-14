<script lang="ts">
    import { onMount } from 'svelte';
    import { goto } from '$app/navigation';
    import { supabaseBrowser } from '$lib/supabase-browser';
    import ExportDialog from '$lib/registry/ExportDialog.svelte';
    import {
        STATUS_LABEL, STATUS_STYLE, FAITH_LABEL, errText, loadCodes, codesOf, age,
        type Code, type PersonRow, type RegistryMe
    } from '$lib/registry';

    let { me }: { me: RegistryMe } = $props();

    type Group = { community_id: number; community_name: string; group_id: number | null; group_name: string | null; group_active: boolean | null };

    const PAGE = 50;

    let codes = $state<Code[]>([]);
    let groups = $state<Group[]>([]);
    const communities = $derived(
        [...new Map(groups.map((g) => [g.community_id, g.community_name])).entries()].map(([id, name]) => ({ id, name }))
    );

    let q = $state('');
    let status = $state<string[]>(['active', 'hold']);
    let faith = $state('');
    let office = $state('');
    let communityId = $state('');
    let groupId = $state('');
    let gender = $state('');

    const groupOptions = $derived(
        groups.filter((g) => g.group_id && (!communityId || String(g.community_id) === communityId))
    );

    let rows = $state<PersonRow[]>([]);
    let total = $state(0);
    let loading = $state(true);
    let errorMsg = $state('');
    let exportOpen = $state(false);

    function filters() {
        const f: Record<string, unknown> = {};
        if (q.trim()) f.q = q.trim();
        if (status.length) f.status = status;
        if (faith) f.faith = [faith];
        if (office) f.office = [office];
        if (groupId) f.group_id = Number(groupId);
        else if (communityId) f.community_id = Number(communityId);
        if (gender) f.gender = gender;
        return f;
    }

    let seq = 0;
    async function search(reset = true) {
        const mine = ++seq;
        loading = true;
        const offset = reset ? 0 : rows.length;
        const { data, error } = await supabaseBrowser.rpc('registry_search', {
            p_filters: filters(), p_limit: PAGE, p_offset: offset
        });
        if (mine !== seq) return; // 늦게 온 옛 요청 폐기
        loading = false;
        if (error) {
            errorMsg = errText(error, '검색하지 못했습니다.');
            return;
        }
        errorMsg = '';
        const got = (data ?? []) as PersonRow[];
        rows = reset ? got : [...rows, ...got];
        total = got[0]?.total ?? (reset ? 0 : total);
    }

    let timer: ReturnType<typeof setTimeout> | undefined;
    function onQuery() {
        clearTimeout(timer);
        timer = setTimeout(() => search(true), 350);
    }

    function toggleStatus(s: string) {
        status = status.includes(s) ? status.filter((x) => x !== s) : [...status, s];
        search(true);
    }

    onMount(async () => {
        const [c, g] = await Promise.all([loadCodes(), supabaseBrowser.rpc('registry_groups')]);
        codes = c;
        groups = (g.data ?? []) as Group[];
        await search(true);
    });
</script>

<div class="rounded-2xl border border-gray-100 bg-gray-50 px-4 py-4 mb-5 space-y-3">
    <div class="flex flex-wrap gap-3 items-end">
        <div class="flex-1 min-w-[14rem]">
            <label for="rq" class="block text-xs font-bold text-gray-600 mb-1.5">이름·전화번호</label>
            <input id="rq" type="text" bind:value={q} oninput={onQuery} placeholder="여러 명은 쉼표로 (예: 김철수, 이영희)"
                class="w-full px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium text-sm" />
        </div>
        <div>
            <label for="rc" class="block text-xs font-bold text-gray-600 mb-1.5">공동체</label>
            <select id="rc" bind:value={communityId} onchange={() => { groupId = ''; search(true); }}
                class="px-3 py-2.5 rounded-xl border-2 border-gray-200 bg-white text-sm">
                <option value="">전체</option>
                {#each communities as c}<option value={String(c.id)}>{c.name}</option>{/each}
            </select>
        </div>
        <div>
            <label for="rg" class="block text-xs font-bold text-gray-600 mb-1.5">소그룹</label>
            <select id="rg" bind:value={groupId} onchange={() => search(true)}
                class="px-3 py-2.5 rounded-xl border-2 border-gray-200 bg-white text-sm">
                <option value="">전체</option>
                {#each groupOptions as g}<option value={String(g.group_id)}>{g.group_name}{g.group_active ? '' : ' (닫힘)'}</option>{/each}
            </select>
        </div>
        <div>
            <label for="ro" class="block text-xs font-bold text-gray-600 mb-1.5">직분</label>
            <select id="ro" bind:value={office} onchange={() => search(true)}
                class="px-3 py-2.5 rounded-xl border-2 border-gray-200 bg-white text-sm">
                <option value="">전체</option>
                {#each codesOf(codes, 'office') as c}<option value={c.code}>{c.label}</option>{/each}
                <option value="none">직분 없음</option>
            </select>
        </div>
        <div>
            <label for="rf" class="block text-xs font-bold text-gray-600 mb-1.5">신급</label>
            <select id="rf" bind:value={faith} onchange={() => search(true)}
                class="px-3 py-2.5 rounded-xl border-2 border-gray-200 bg-white text-sm">
                <option value="">전체</option>
                {#each Object.entries(FAITH_LABEL) as [k, v]}<option value={k}>{v}</option>{/each}
            </select>
        </div>
        <div>
            <label for="rs" class="block text-xs font-bold text-gray-600 mb-1.5">성별</label>
            <select id="rs" bind:value={gender} onchange={() => search(true)}
                class="px-3 py-2.5 rounded-xl border-2 border-gray-200 bg-white text-sm">
                <option value="">전체</option>
                <option value="남">남</option>
                <option value="여">여</option>
            </select>
        </div>
    </div>
    <div class="flex flex-wrap items-center gap-1.5">
        <span class="text-xs font-bold text-gray-600 mr-1">재적 상태</span>
        {#each Object.entries(STATUS_LABEL) as [k, v]}
            <button type="button" onclick={() => toggleStatus(k)}
                class="px-3 py-1 rounded-full text-xs font-bold border transition-colors
                {status.includes(k) ? 'bg-primary-900 border-primary-900 text-white' : 'bg-white border-gray-200 text-gray-500 hover:border-gray-400'}">
                {v}
            </button>
        {/each}
        {#if status.length === 0}<span class="text-xs text-gray-400 ml-1">(상태 전체)</span>{/if}
    </div>
</div>

{#if errorMsg}
    <div class="mb-5 bg-red-50 border border-red-100 text-red-600 text-sm rounded-xl px-4 py-3">{errorMsg}</div>
{/if}

<div class="flex items-center justify-between mb-3">
    <p class="text-sm text-gray-500"><b class="text-gray-900">{total}</b>명</p>
    <div class="flex items-center gap-2">
        {#if me.can_export}
            <button type="button" onclick={() => (exportOpen = true)} disabled={total === 0 || loading}
                class="px-4 py-2 rounded-xl border border-gray-200 bg-white font-bold text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-40">내려받기</button>
        {/if}
        {#if me.can_edit}
            <a href="/registry/new" class="px-4 py-2 rounded-xl bg-gray-900 text-white font-bold text-sm hover:bg-gray-700">+ 새가족 등록</a>
        {/if}
    </div>
</div>

{#if exportOpen}
    <ExportDialog filters={filters()} {total} {codes} onclose={() => (exportOpen = false)} />
{/if}

{#if loading && rows.length === 0}
    <div class="py-16 text-center text-gray-400 text-sm">불러오는 중…</div>
{:else if rows.length === 0}
    <div class="py-16 text-center text-gray-400 text-sm">조건에 맞는 교인이 없습니다.</div>
{:else}
    <div class="rounded-2xl border border-gray-200 overflow-x-auto">
        <table class="w-full text-sm min-w-[52rem]">
            <thead class="bg-gray-50 text-xs text-gray-500">
                <tr>
                    <th class="text-left font-bold px-4 py-2.5">이름</th>
                    <th class="text-left font-bold px-3 py-2.5">직분</th>
                    <th class="text-left font-bold px-3 py-2.5">성별·나이</th>
                    <th class="text-left font-bold px-3 py-2.5">공동체·소그룹</th>
                    <th class="text-left font-bold px-3 py-2.5">상태</th>
                    <th class="text-left font-bold px-3 py-2.5">신급</th>
                    <th class="text-left font-bold px-3 py-2.5">전화</th>
                    <th class="text-left font-bold px-3 py-2.5">앱</th>
                </tr>
            </thead>
            <tbody>
                {#each rows as r (r.person_id)}
                    {@const a = age(r.birth_date)}
                    <tr class="border-t border-gray-50 hover:bg-primary-50/40 cursor-pointer" onclick={() => goto(`/registry/${r.person_id}`)}>
                        <td class="px-4 py-2.5">
                            <a href={`/registry/${r.person_id}`} class="font-bold text-gray-900 hover:text-primary-700">{r.name ?? '(이름없음)'}</a>
                            {#if r.name_note}<span class="text-xs text-gray-400 ml-1">{r.name_note}</span>{/if}
                        </td>
                        <td class="px-3 py-2.5 text-gray-600">{r.office ?? ''}</td>
                        <td class="px-3 py-2.5 text-gray-600">{r.gender ?? '-'}{a !== null ? ` · ${a}세` : ''}</td>
                        <td class="px-3 py-2.5 text-gray-600">{r.community_name ? `${r.community_name} · ${r.group_name}` : '-'}</td>
                        <td class="px-3 py-2.5">
                            <span class="px-2 py-0.5 rounded-full text-xs font-bold {STATUS_STYLE[r.status] ?? ''}">{STATUS_LABEL[r.status] ?? r.status}</span>
                        </td>
                        <td class="px-3 py-2.5 text-gray-600 {r.faith === 'unknown' ? 'text-gray-400' : ''}">{FAITH_LABEL[r.faith] ?? r.faith}</td>
                        <td class="px-3 py-2.5 text-gray-600 whitespace-nowrap">{r.phone ?? ''}</td>
                        <td class="px-3 py-2.5 text-xs text-gray-400">{r.has_account ? '가입' : ''}</td>
                    </tr>
                {/each}
            </tbody>
        </table>
    </div>
    {#if rows.length < total}
        <div class="text-center mt-4">
            <button type="button" onclick={() => search(false)} disabled={loading}
                class="px-5 py-2 rounded-xl border border-gray-200 text-sm font-bold text-gray-600 hover:bg-gray-50 disabled:opacity-50">
                더 보기 ({rows.length}/{total})
            </button>
        </div>
    {/if}
{/if}
