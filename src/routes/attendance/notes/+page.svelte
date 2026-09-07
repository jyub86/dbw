<script lang="ts">
    import { onMount } from 'svelte';
    import { goto } from '$app/navigation';
    import { supabaseBrowser } from '$lib/supabase-browser';
    import { loadAccess, fetchAll, fmtDate, todayISO } from '$lib/attendance';
    import AttendanceNav from '$lib/components/AttendanceNav.svelte';

    // 주차가 쌓여도 첫 로딩이 무거워지지 않도록 최근 N주만 먼저 불러오고 이후 추가 로딩한다.
    const PAGE_WEEKS = 8;

    type Community = { name: string; sort_order: number };
    type Group = {
        id: number; name: string; sort_order: number; community_id: number;
        communities: Community | null;
    };
    type Session = { id: number; session_date: string };
    // PostgREST 의 to-one 임베드는 런타임에 객체 하나로 오지만 생성 타입은 배열로 추론된다.
    // 양쪽을 다 받아두고 one() 으로 정규화한다.
    type Embed<T> = T | T[] | null;
    type UserRef = { name: string | null; office: string | null };
    type MemberRef = { role: string; custom_users: Embed<UserRef> };
    type MemberNote = {
        member_id: number; session_id: number; small_group_id: number; note: string;
        small_group_members: Embed<MemberRef>;
    };
    type GroupNote = { small_group_id: number; session_id: number; note: string };

    const one = <T,>(v: Embed<T>): T | null => (Array.isArray(v) ? (v[0] ?? null) : (v ?? null));
    function who(n: MemberNote) {
        const m = one(n.small_group_members);
        const u = m ? one(m.custom_users) : null;
        return {
            name: u?.name ?? '(이름없음)',
            office: u?.office ?? '',
            role: m?.role ?? 'member'
        };
    }

    let loading = $state(true);
    let loadingMore = $state(false);
    let denied = $state(false);
    let errorMsg = $state('');

    let sessions = $state<Session[]>([]); // 전체 과거 주차 (최신순) — 메타만이라 가볍다
    let loadedCount = $state(0); // 노트를 불러온 주차 수 (sessions 앞에서부터)
    let groups = $state<Group[]>([]);
    let memberNotes = $state<MemberNote[]>([]);
    let groupNotes = $state<GroupNote[]>([]);

    // 보기 방식 · 필터
    let viewMode = $state<'week' | 'person'>('week');
    let fCommunity = $state<number | 'all'>('all');
    let fGroup = $state<number | 'all'>('all');
    let fSession = $state<number | 'all'>('all');
    let query = $state('');

    const groupById = $derived(new Map(groups.map((g) => [g.id, g])));
    const loadedSessions = $derived(sessions.slice(0, loadedCount));
    const hasMore = $derived(loadedCount < sessions.length);

    const communities = $derived(
        [...new Map(groups.map((g) => [g.community_id, g.communities])).entries()]
            .map(([id, c]) => ({ id, name: c?.name ?? '', sort: c?.sort_order ?? 0 }))
            .sort((a, b) => a.sort - b.sort)
    );
    const groupOptions = $derived(
        groups
            .filter((g) => fCommunity === 'all' || g.community_id === fCommunity)
            .slice()
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
    const dateOf = $derived(new Map(sessions.map((s) => [s.id, s.session_date])));
    const label = (gid: number) => {
        const g = groupById.get(gid);
        return g ? `${g.communities?.name ?? ''} · ${g.name}` : '';
    };

    // ── 주차별 보기 ──────────────────────────────
    type GroupBlock = {
        group: Group;
        groupNote: string | null;
        items: { name: string; office: string; role: string; note: string }[];
    };
    type WeekBlock = { session: Session; blocks: GroupBlock[]; count: number };

    const weeks = $derived.by<WeekBlock[]>(() => {
        const out: WeekBlock[] = [];
        for (const s of loadedSessions) {
            const blocks: GroupBlock[] = [];
            for (const g of groups) {
                if (!passes(g.id, s.id)) continue;
                const gn = groupNotes.find((x) => x.small_group_id === g.id && x.session_id === s.id);
                const gnText = gn && hit(gn.note) ? gn.note : null;
                const items = memberNotes
                    .filter((n) => n.small_group_id === g.id && n.session_id === s.id && hit(n.note))
                    .map((n) => ({ ...who(n), note: n.note }))
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
            out.push({
                session: s,
                blocks,
                count: blocks.reduce((acc, b) => acc + b.items.length + (b.groupNote ? 1 : 0), 0)
            });
        }
        return out;
    });

    // ── 인원별 보기 ──────────────────────────────
    type PersonBlock = {
        memberId: number; name: string; office: string; role: string; where: string;
        items: { date: string; note: string }[];
    };
    const persons = $derived.by<PersonBlock[]>(() => {
        const map = new Map<number, PersonBlock>();
        for (const n of memberNotes) {
            if (!passes(n.small_group_id, n.session_id)) continue;
            if (!hit(n.note)) continue;
            const date = dateOf.get(n.session_id);
            if (!date) continue; // 불러오지 않은 주차
            let p = map.get(n.member_id);
            if (!p) {
                p = { memberId: n.member_id, ...who(n), where: label(n.small_group_id), items: [] };
                map.set(n.member_id, p);
            }
            p.items.push({ date, note: n.note });
        }
        const out = [...map.values()];
        for (const p of out) p.items.sort((a, b) => (a.date < b.date ? 1 : -1)); // 최근순
        // 기록이 많은 사람 우선 (돌봄이 필요한 인원이 위로)
        return out.sort((a, b) => b.items.length - a.items.length || a.name.localeCompare(b.name, 'ko'));
    });

    // 인원별 보기에서도 그룹 단위 '기타 의견'이 묻히지 않도록 별도 목록으로 낸다.
    type GroupNoteRow = { where: string; date: string; note: string; co: number; go: number };
    const groupNoteRows = $derived.by<GroupNoteRow[]>(() =>
        groupNotes
            .filter((n) => passes(n.small_group_id, n.session_id) && hit(n.note) && dateOf.has(n.session_id))
            .map((n) => {
                const g = groupById.get(n.small_group_id);
                return {
                    where: label(n.small_group_id),
                    date: dateOf.get(n.session_id) ?? '',
                    note: n.note,
                    co: g?.communities?.sort_order ?? 0,
                    go: g?.sort_order ?? 0
                };
            })
            .sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : a.co - b.co || a.go - b.go))
    );

    const totalCount = $derived(
        viewMode === 'week'
            ? weeks.reduce((a, w) => a + w.count, 0)
            : persons.reduce((a, p) => a + p.items.length, 0) + groupNoteRows.length
    );
    const totalGroups = $derived(
        new Set(
            memberNotes
                .filter((n) => passes(n.small_group_id, n.session_id) && hit(n.note) && dateOf.has(n.session_id))
                .map((n) => n.small_group_id)
                .concat(
                    groupNotes
                        .filter((n) => passes(n.small_group_id, n.session_id) && hit(n.note) && dateOf.has(n.session_id))
                        .map((n) => n.small_group_id)
                )
        ).size
    );

    async function fetchNotes(sessionIds: number[]) {
        if (sessionIds.length === 0) return { mn: [] as MemberNote[], gn: [] as GroupNote[] };
        const [mn, gn] = await Promise.all([
            fetchAll<MemberNote>((f, t) =>
                supabaseBrowser
                    .from('member_notes')
                    .select('member_id, session_id, small_group_id, note, small_group_members(role, custom_users(name, office))')
                    .in('session_id', sessionIds)
                    .order('id')
                    .range(f, t)
            ),
            fetchAll<GroupNote>((f, t) =>
                supabaseBrowser
                    .from('group_session_notes')
                    .select('small_group_id, session_id, note')
                    .in('session_id', sessionIds)
                    .order('id')
                    .range(f, t)
            )
        ]);
        return { mn, gn };
    }

    async function loadMore(all = false) {
        if (loadingMore || !hasMore) return;
        loadingMore = true;
        const to = all ? sessions.length : Math.min(loadedCount + PAGE_WEEKS, sessions.length);
        const ids = sessions.slice(loadedCount, to).map((s) => s.id);
        try {
            const { mn, gn } = await fetchNotes(ids);
            memberNotes = [...memberNotes, ...mn];
            groupNotes = [...groupNotes, ...gn];
            loadedCount = to;
        } catch {
            errorMsg = '추가 기록을 불러오지 못했습니다.';
        }
        loadingMore = false;
    }

    onMount(async () => {
        const { hasSession, access } = await loadAccess();
        if (!hasSession) return goto('/login');
        // 특이사항은 교역자/관리자만 (통계 열람자는 RLS 로도 막혀 있음)
        if (!access || !access.canManage) {
            denied = true;
            loading = false;
            return;
        }

        const [{ data: ss }, { data: gs }] = await Promise.all([
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
                .order('sort_order')
        ]);
        sessions = (ss ?? []) as Session[];
        groups = (gs ?? []) as unknown as Group[];
        if (!ss || !gs) errorMsg = '일부 데이터를 불러오지 못했습니다.';

        const first = sessions.slice(0, PAGE_WEEKS).map((s) => s.id);
        const { mn, gn } = await fetchNotes(first);
        memberNotes = mn;
        groupNotes = gn;
        loadedCount = Math.min(PAGE_WEEKS, sessions.length);
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
    <p class="text-gray-500 mb-6 text-sm sm:text-base">전체 소그룹에서 올라온 기록을 주차별 또는 인원별로 모아 봅니다.</p>

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

        <!-- 보기 방식 -->
        <div class="flex gap-1 mb-4 bg-gray-100 rounded-2xl p-1 w-fit">
            <button type="button" onclick={() => (viewMode = 'week')}
                class="px-4 py-2 rounded-xl text-sm font-bold transition-colors {viewMode === 'week' ? 'bg-white text-primary-800 shadow-sm' : 'text-gray-500 hover:text-gray-800'}">주차별</button>
            <button type="button" onclick={() => (viewMode = 'person')}
                class="px-4 py-2 rounded-xl text-sm font-bold transition-colors {viewMode === 'person' ? 'bg-white text-primary-800 shadow-sm' : 'text-gray-500 hover:text-gray-800'}">인원별</button>
        </div>

        <!-- 필터 -->
        <div class="rounded-2xl border border-gray-100 bg-gray-50 px-4 py-4 mb-5 flex flex-wrap items-end gap-3">
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
                <label for="fs" class="block text-[11px] font-bold text-gray-600 mb-1">주차 <span class="font-normal text-gray-400">(불러온 범위)</span></label>
                <select id="fs" class="px-3 py-2 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium text-sm"
                    value={fSession}
                    onchange={(e) => { const v = (e.currentTarget as HTMLSelectElement).value; fSession = v === 'all' ? 'all' : Number(v); }}>
                    <option value="all">전체</option>
                    {#each loadedSessions as s}<option value={s.id}>{fmtDate(s.session_date)}</option>{/each}
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

        <div class="flex items-baseline justify-between gap-3 flex-wrap mb-4">
            <p class="text-sm text-gray-500">
                <b class="text-gray-900">{totalCount}</b>건 · {totalGroups}개 소그룹
                <span class="text-gray-400">· 최근 {loadedCount}주 조회{#if hasMore} (전체 {sessions.length}주){/if}</span>
            </p>
            {#if loadingMore}<span class="text-xs text-gray-400">불러오는 중…</span>{/if}
        </div>

        {#if viewMode === 'week'}
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
        {:else}
            <!-- 인원별 -->
            {#if persons.length === 0 && groupNoteRows.length === 0}
                <div class="py-16 text-center text-gray-400 text-sm">조건에 맞는 기록이 없습니다.</div>
            {:else}
                <div class="space-y-3 mb-10">
                    {#each persons as p (p.memberId)}
                        <div class="rounded-2xl border border-gray-200 bg-white overflow-hidden">
                            <div class="flex items-center gap-2 px-4 py-2.5 bg-gray-50 flex-wrap">
                                <span class="font-black text-gray-900">{p.name}</span>
                                {#if p.role === 'leader'}<span class="text-[10px] font-bold text-white bg-primary-600 px-1.5 py-0.5 rounded">리더</span>{/if}
                                <span class="text-[11px] text-gray-400">{p.office}</span>
                                <span class="text-[11px] font-bold text-primary-700">{p.where}</span>
                                <span class="ml-auto text-[11px] font-bold text-gray-400">{p.items.length}건</span>
                            </div>
                            {#each p.items as it}
                                <div class="flex gap-3 px-4 py-2.5 border-b border-gray-50 last:border-0">
                                    <span class="shrink-0 w-16 text-xs font-bold text-primary-700">{fmtDate(it.date)}</span>
                                    <p class="flex-1 text-sm text-gray-700 whitespace-pre-wrap break-words">{it.note}</p>
                                </div>
                            {/each}
                        </div>
                    {/each}
                </div>

                {#if groupNoteRows.length > 0}
                    <section class="mb-8">
                        <h2 class="text-lg font-black text-gray-900 mb-1">그룹 기타 의견</h2>
                        <p class="text-xs text-gray-400 mb-3">소그룹 단위 기록이라 특정 인원에 속하지 않습니다.</p>
                        <div class="space-y-2">
                            {#each groupNoteRows as r, i (r.where + r.date + i)}
                                <div class="rounded-2xl border border-gray-200 bg-amber-50/40 px-4 py-3">
                                    <div class="flex items-baseline gap-2 mb-1">
                                        <span class="text-[11px] font-bold text-primary-700">{r.where}</span>
                                        <span class="text-[11px] text-gray-400">{fmtDate(r.date)}</span>
                                    </div>
                                    <p class="text-sm text-gray-700 whitespace-pre-wrap break-words">{r.note}</p>
                                </div>
                            {/each}
                        </div>
                    </section>
                {/if}
            {/if}
        {/if}

        {#if hasMore}
            <div class="flex items-center justify-center gap-2 py-6">
                <button type="button" onclick={() => loadMore(false)} disabled={loadingMore}
                    class="px-5 py-2.5 rounded-xl bg-primary-900 text-white font-bold text-sm hover:bg-primary-800 disabled:opacity-50">
                    이전 {Math.min(PAGE_WEEKS, sessions.length - loadedCount)}주 더 보기
                </button>
                <button type="button" onclick={() => loadMore(true)} disabled={loadingMore}
                    class="px-4 py-2.5 rounded-xl border-2 border-gray-200 text-gray-600 font-bold text-sm hover:bg-gray-50 disabled:opacity-50">
                    전체 {sessions.length}주 불러오기
                </button>
            </div>
        {:else if sessions.length > 0}
            <p class="py-6 text-center text-xs text-gray-400">전체 {sessions.length}주를 모두 불러왔습니다.</p>
        {/if}
    {/if}
</div>
