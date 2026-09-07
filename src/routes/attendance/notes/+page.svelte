<script lang="ts">
    import { onMount } from 'svelte';
    import { goto } from '$app/navigation';
    import { supabaseBrowser } from '$lib/supabase-browser';
    import { loadAccess, fetchAll, fmtDate, todayISO } from '$lib/attendance';
    import AttendanceNav from '$lib/components/AttendanceNav.svelte';

    type Community = { name: string; sort_order: number };
    type Group = {
        id: number; name: string; sort_order: number; community_id: number;
        communities: Community | null;
    };
    type Member = {
        id: number; small_group_id: number; role: string;
        custom_users: { name: string | null; office: string | null } | null;
    };
    type Session = { id: number; session_date: string };
    type MemberNote = { member_id: number; session_id: number; small_group_id: number; note: string };
    type GroupNote = { small_group_id: number; session_id: number; note: string };

    let loading = $state(true);
    let denied = $state(false);
    let errorMsg = $state('');

    let sessions = $state<Session[]>([]);
    let groups = $state<Group[]>([]);
    let members = $state<Member[]>([]);
    let memberNotes = $state<MemberNote[]>([]);
    let groupNotes = $state<GroupNote[]>([]);

    // 필터
    let fCommunity = $state<number | 'all'>('all');
    let fGroup = $state<number | 'all'>('all');
    let fSession = $state<number | 'all'>('all');
    let query = $state('');

    const groupById = $derived(new Map(groups.map((g) => [g.id, g])));
    const memberById = $derived(new Map(members.map((m) => [m.id, m])));
    const communities = $derived(
        [...new Map(groups.map((g) => [g.community_id, g.communities])).entries()]
            .map(([id, c]) => ({ id, name: c?.name ?? '', sort: c?.sort_order ?? 0 }))
            .sort((a, b) => a.sort - b.sort)
    );
    // 공동체 필터를 반영한 소그룹 선택지
    const groupOptions = $derived(
        groups
            .filter((g) => fCommunity === 'all' || g.community_id === fCommunity)
            .sort((a, b) => a.sort_order - b.sort_order)
    );

    function hit(text: string) {
        const q = query.trim().toLowerCase();
        return !q || text.toLowerCase().includes(q);
    }
    function passes(gid: number, sid: number) {
        const g = groupById.get(gid);
        if (!g) return false;
        if (fCommunity !== 'all' && g.community_id !== fCommunity) return false;
        if (fGroup !== 'all' && gid !== fGroup) return false;
        if (fSession !== 'all' && sid !== fSession) return false;
        return true;
    }

    type GroupBlock = {
        group: Group;
        groupNote: string | null;
        items: { name: string; office: string; role: string; note: string }[];
    };
    type WeekBlock = { session: Session; blocks: GroupBlock[]; count: number };

    // 주차(최근순) → 공동체·소그룹 순으로 묶는다.
    const weeks = $derived.by<WeekBlock[]>(() => {
        const out: WeekBlock[] = [];
        for (const s of sessions) {
            const blocks: GroupBlock[] = [];
            for (const g of groups) {
                if (!passes(g.id, s.id)) continue;
                const gn = groupNotes.find((x) => x.small_group_id === g.id && x.session_id === s.id);
                const gnText = gn && hit(gn.note) ? gn.note : null;
                const items = memberNotes
                    .filter((n) => n.small_group_id === g.id && n.session_id === s.id && hit(n.note))
                    .map((n) => {
                        const m = memberById.get(n.member_id);
                        return {
                            name: m?.custom_users?.name ?? '(이름없음)',
                            office: m?.custom_users?.office ?? '',
                            role: m?.role ?? 'member',
                            note: n.note
                        };
                    })
                    .sort((a, b) => a.name.localeCompare(b.name, 'ko'));
                if (!gnText && items.length === 0) continue;
                blocks.push({ group: g, groupNote: gnText, items });
            }
            if (blocks.length === 0) continue;
            blocks.sort(
                (a, b) =>
                    (a.group.communities?.sort_order ?? 0) - (b.group.communities?.sort_order ?? 0) ||
                    a.group.sort_order - b.group.sort_order
            );
            const count = blocks.reduce((acc, b) => acc + b.items.length + (b.groupNote ? 1 : 0), 0);
            out.push({ session: s, blocks, count });
        }
        return out;
    });

    const totalCount = $derived(weeks.reduce((a, w) => a + w.count, 0));
    const totalGroups = $derived(new Set(weeks.flatMap((w) => w.blocks.map((b) => b.group.id))).size);

    onMount(async () => {
        const { hasSession, access } = await loadAccess();
        if (!hasSession) return goto('/login');
        // 특이사항은 교역자/관리자만 (통계 열람자는 RLS 로도 막혀 있음)
        if (!access || !access.canManage) {
            denied = true;
            loading = false;
            return;
        }

        const [{ data: ss }, { data: gs }, { data: ms }, mn, gn] = await Promise.all([
            supabaseBrowser
                .from('attendance_sessions')
                .select('id, session_date')
                .eq('active', true)
                .lte('session_date', todayISO())
                .order('session_date', { ascending: false }),
            supabaseBrowser
                .from('small_groups')
                .select('id, name, sort_order, community_id, communities(name, sort_order)')
                .eq('active', true)
                .order('sort_order'),
            // 메모 작성 후 제외된 인원의 이름도 보여야 하므로 active 로 거르지 않는다
            supabaseBrowser
                .from('small_group_members')
                .select('id, small_group_id, role, custom_users(name, office)'),
            fetchAll<MemberNote>((f, t) =>
                supabaseBrowser
                    .from('member_notes')
                    .select('member_id, session_id, small_group_id, note')
                    .order('id')
                    .range(f, t)
            ),
            fetchAll<GroupNote>((f, t) =>
                supabaseBrowser
                    .from('group_session_notes')
                    .select('small_group_id, session_id, note')
                    .order('id')
                    .range(f, t)
            )
        ]);

        sessions = (ss ?? []) as Session[];
        groups = (gs ?? []) as unknown as Group[];
        members = (ms ?? []) as unknown as Member[];
        memberNotes = mn;
        groupNotes = gn;
        if (!ss || !gs) errorMsg = '일부 데이터를 불러오지 못했습니다.';
        loading = false;
    });

    function resetFilters() {
        fCommunity = 'all';
        fGroup = 'all';
        fSession = 'all';
        query = '';
    }
</script>

<svelte:head><title>특이사항 모아보기 - 부평동부교회</title></svelte:head>

<div class="w-full max-w-7xl mx-auto px-6 sm:px-8 lg:px-12 py-10 sm:py-14">
    <h1 class="text-2xl sm:text-3xl font-black text-gray-900 mb-1">특이사항 · 기타 의견 모아보기</h1>
    <p class="text-gray-500 mb-6 text-sm sm:text-base">전체 소그룹에서 올라온 기록을 주차별로 모아 봅니다.</p>

    <AttendanceNav canCheck={true} canViewStats={true} canManage={true} />

    {#if loading}
        <div class="py-20 text-center text-gray-400">불러오는 중…</div>
    {:else if denied}
        <div class="py-20 text-center">
            <p class="text-gray-500 font-medium">접근 권한이 없습니다.</p>
            <p class="text-gray-400 text-sm mt-2">교역자 또는 관리자만 볼 수 있습니다.</p>
            <a href="/attendance" class="inline-block mt-6 px-6 py-2.5 rounded-full bg-primary-900 text-white font-bold text-sm">출석 체크로</a>
        </div>
    {:else}
        {#if errorMsg}
            <div class="mb-5 bg-red-50 border border-red-100 text-red-600 text-sm rounded-xl px-4 py-3">{errorMsg}</div>
        {/if}

        <!-- 필터 -->
        <div class="rounded-2xl border border-gray-100 bg-gray-50 px-4 py-4 mb-6 flex flex-wrap items-end gap-3">
            <div>
                <label for="fc" class="block text-[11px] font-bold text-gray-600 mb-1">공동체</label>
                <select id="fc" class="px-3 py-2 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium text-sm"
                    value={fCommunity}
                    onchange={(e) => { const v = (e.currentTarget as HTMLSelectElement).value; fCommunity = v === 'all' ? 'all' : Number(v); fGroup = 'all'; }}>
                    <option value="all">전체</option>
                    {#each communities as c}<option value={c.id}>{c.name}</option>{/each}
                </select>
            </div>
            <div>
                <label for="fg" class="block text-[11px] font-bold text-gray-600 mb-1">소그룹</label>
                <select id="fg" class="px-3 py-2 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium text-sm"
                    value={fGroup}
                    onchange={(e) => { const v = (e.currentTarget as HTMLSelectElement).value; fGroup = v === 'all' ? 'all' : Number(v); }}>
                    <option value="all">전체</option>
                    {#each groupOptions as g}<option value={g.id}>{g.name}</option>{/each}
                </select>
            </div>
            <div>
                <label for="fs" class="block text-[11px] font-bold text-gray-600 mb-1">주차</label>
                <select id="fs" class="px-3 py-2 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium text-sm"
                    value={fSession}
                    onchange={(e) => { const v = (e.currentTarget as HTMLSelectElement).value; fSession = v === 'all' ? 'all' : Number(v); }}>
                    <option value="all">전체</option>
                    {#each sessions as s}<option value={s.id}>{fmtDate(s.session_date)}</option>{/each}
                </select>
            </div>
            <div class="flex-1 min-w-[180px]">
                <label for="fq" class="block text-[11px] font-bold text-gray-600 mb-1">검색</label>
                <input id="fq" type="text" placeholder="내용으로 검색" bind:value={query}
                    class="w-full px-3 py-2 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white text-sm" />
            </div>
            <button type="button" onclick={resetFilters}
                class="px-4 py-2 rounded-xl border-2 border-gray-200 text-gray-600 font-bold text-sm hover:bg-white">초기화</button>
        </div>

        <p class="text-sm text-gray-500 mb-4">
            <b class="text-gray-900">{totalCount}</b>건 · {totalGroups}개 소그룹 · {weeks.length}개 주차
        </p>

        {#if weeks.length === 0}
            <div class="py-16 text-center text-gray-400 text-sm">조건에 맞는 기록이 없습니다.</div>
        {:else}
            {#each weeks as w (w.session.id)}
                <section class="mb-8">
                    <div class="flex items-baseline gap-2 mb-3">
                        <h2 class="text-lg font-black text-gray-900">{fmtDate(w.session.session_date)}</h2>
                        <span class="text-xs text-gray-400 font-bold">{w.count}건</span>
                    </div>
                    <div class="space-y-3">
                        {#each w.blocks as b (b.group.id)}
                            <div class="rounded-2xl border border-gray-200 bg-white overflow-hidden">
                                <div class="flex items-center gap-2 px-4 py-2.5 bg-primary-50">
                                    <span class="text-[11px] font-bold text-primary-700">{b.group.communities?.name ?? ''}</span>
                                    <span class="font-black text-primary-900">{b.group.name}</span>
                                </div>
                                {#if b.groupNote}
                                    <div class="px-4 py-3 border-b border-gray-100 bg-amber-50/50">
                                        <div class="text-[11px] font-bold text-amber-700 mb-1">기타 의견</div>
                                        <p class="text-sm text-gray-700 whitespace-pre-wrap break-words">{b.groupNote}</p>
                                    </div>
                                {/if}
                                {#each b.items as it}
                                    <div class="flex gap-3 px-4 py-2.5 border-b border-gray-50 last:border-0">
                                        <div class="shrink-0 w-28">
                                            <span class="font-bold text-gray-900 text-sm">{it.name}</span>
                                            {#if it.role === 'leader'}<span class="ml-1 text-[10px] font-bold text-primary-700">리더</span>{/if}
                                            <div class="text-[11px] text-gray-400">{it.office}</div>
                                        </div>
                                        <p class="flex-1 text-sm text-gray-700 whitespace-pre-wrap break-words">{it.note}</p>
                                    </div>
                                {/each}
                            </div>
                        {/each}
                    </div>
                </section>
            {/each}
        {/if}
    {/if}
</div>
