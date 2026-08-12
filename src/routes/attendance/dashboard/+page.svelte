<script lang="ts">
    import { onMount } from 'svelte';
    import { goto } from '$app/navigation';
    import { supabaseBrowser } from '$lib/supabase-browser';
    import { loadAccess, fmtDate, todayISO } from '$lib/attendance';
    import AttendanceNav from '$lib/components/AttendanceNav.svelte';

    type Sess = { id: number; session_date: string };
    type Community = { id: number; name: string; sort_order: number };
    type GroupStat = {
        id: number; community_id?: number; community: string; name: string;
        present: number; members: number; recorded?: number; rate: number;
    };
    type CommStat = { id: number; name: string; present?: number; members: number; rate: number };
    type WeekData = {
        session_id: number; session_date: string;
        overall: { present: number; members: number; rate: number };
        communities: CommStat[]; groups: GroupStat[];
    };
    type FullData = {
        overall: { present: number; rate: number };
        communities: CommStat[]; groups: GroupStat[];
    };
    type TrendPoint = { date?: string; ym?: string; present: number; members: number; rate: number };

    let loading = $state(true);
    let denied = $state(false);
    let canManage = $state(false); // 관리자/교역자 여부 (탭 노출용)
    let errorMsg = $state('');
    let view = $state<'week' | 'trend' | 'full'>('week');

    let sessions = $state<Sess[]>([]); // 과거 주차 (최신순)
    let communities = $state<Community[]>([]);
    let groups = $state<{ id: number; name: string; community_id: number; sort_order: number }[]>([]);

    // 주차별
    let weekSessionId = $state<number | null>(null);
    let weekData = $state<WeekData | null>(null);
    let weekBusy = $state(false);
    let weekFilter = $state<number | 'all'>('all'); // 그룹 표 공동체 필터

    // 추이
    let trendMode = $state<'weekly' | 'monthly'>('weekly');
    let trendCommunity = $state<number | 'all'>('all');
    let trendGroup = $state<number | 'all'>('all');
    let trendData = $state<TrendPoint[]>([]);
    let trendBusy = $state(false);

    // 전체 통계
    let fullCommunity = $state<number | 'all'>('all');
    let fullData = $state<FullData | null>(null);
    let fullBusy = $state(false);

    // 공동체(열매→줄기→뿌리)별로 묶고, 그룹은 출석률 내림차순 (주차별·전체 통계 공용)
    function groupByCommunity(filterId: number | 'all', dataComms: CommStat[], dataGroups: GroupStat[]) {
        return communities
            .filter((c) => filterId === 'all' || c.id === filterId)
            .map((c) => ({
                community: c,
                stat: dataComms.find((x) => x.id === c.id),
                groups: dataGroups
                    .filter((g) => g.community_id === c.id)
                    .slice()
                    .sort((a, b) => b.rate - a.rate)
            }))
            .filter((x) => x.groups.length > 0);
    }
    const weekByCommunity = $derived(
        groupByCommunity(weekFilter, weekData?.communities ?? [], weekData?.groups ?? [])
    );
    const fullByCommunity = $derived(
        groupByCommunity(fullCommunity, fullData?.communities ?? [], fullData?.groups ?? [])
    );
    // 추이 소그룹 선택지 (공동체 필터 반영)
    const trendGroupOptions = $derived(
        groups.filter((g) => trendCommunity === 'all' || g.community_id === trendCommunity)
    );
    const trendScopeLabel = $derived(
        trendGroup !== 'all'
            ? (groups.find((g) => g.id === trendGroup)?.name ?? '')
            : trendCommunity !== 'all'
              ? (communities.find((c) => c.id === trendCommunity)?.name ?? '')
              : '전체'
    );

    function monthLabel(ym: string) {
        const [, m] = ym.split('-');
        return `${Number(m)}월`;
    }
    function shortDate(iso: string) {
        const [, m, d] = iso.split('-');
        return `${Number(m)}/${Number(d)}`;
    }

    onMount(async () => {
        const { hasSession, access } = await loadAccess();
        if (!hasSession) return goto('/login');
        if (!access || !access.canViewStats) {
            denied = true;
            loading = false;
            return;
        }
        canManage = access.canManage;
        const [{ data: ss }, { data: cs }, { data: gs }] = await Promise.all([
            supabaseBrowser
                .from('attendance_sessions')
                .select('id, session_date')
                .eq('active', true)
                .lte('session_date', todayISO())
                .order('session_date', { ascending: false }),
            supabaseBrowser.from('communities').select('id, name, sort_order').order('sort_order'),
            supabaseBrowser
                .from('small_groups')
                .select('id, name, community_id, sort_order')
                .eq('active', true)
                .order('sort_order')
        ]);
        sessions = (ss ?? []) as Sess[];
        communities = (cs ?? []) as Community[];
        groups = (gs ?? []) as typeof groups;
        weekSessionId = sessions[0]?.id ?? null;
        await loadWeek();
        loading = false;
    });

    // 응답 순서 보장용 토큰 (늦게 도착한 옛 요청이 최신 상태를 덮어쓰지 않도록)
    let weekSeq = 0;
    let trendSeq = 0;
    let fullSeq = 0;

    async function loadWeek() {
        if (!weekSessionId) return;
        const seq = ++weekSeq;
        weekBusy = true;
        errorMsg = '';
        const { data, error } = await supabaseBrowser.rpc('att_week', { p_session_id: weekSessionId });
        if (seq !== weekSeq) return; // 더 새로운 요청이 진행 중 → 폐기
        weekBusy = false;
        if (error || data == null) {
            errorMsg = '주차 통계를 불러오지 못했습니다.';
            weekData = null;
            return;
        }
        weekData = data as WeekData;
    }
    async function loadTrend() {
        const seq = ++trendSeq;
        trendBusy = true;
        errorMsg = '';
        const comm = trendCommunity === 'all' ? null : trendCommunity;
        const grp = trendGroup === 'all' ? null : trendGroup;
        const fn = trendMode === 'weekly' ? 'att_weekly_trend' : 'att_monthly_trend';
        const args =
            trendMode === 'weekly'
                ? { p_weeks: 16, p_community_id: comm, p_group_id: grp }
                : { p_community_id: comm, p_group_id: grp };
        const { data, error } = await supabaseBrowser.rpc(fn, args);
        if (seq !== trendSeq) return;
        trendBusy = false;
        if (error) {
            errorMsg = '추이를 불러오지 못했습니다.';
            trendData = [];
            return;
        }
        trendData = (data ?? []) as TrendPoint[];
    }
    async function loadFull() {
        const seq = ++fullSeq;
        fullBusy = true;
        errorMsg = '';
        const comm = fullCommunity === 'all' ? null : fullCommunity;
        const { data, error } = await supabaseBrowser.rpc('att_full', { p_community_id: comm });
        if (seq !== fullSeq) return;
        fullBusy = false;
        if (error || data == null) {
            errorMsg = '전체 통계를 불러오지 못했습니다.';
            fullData = null;
            return;
        }
        fullData = data as FullData;
    }

    function switchView(v: 'week' | 'trend' | 'full') {
        view = v;
        errorMsg = '';
        if (v === 'trend' && trendData.length === 0) loadTrend();
        if (v === 'full' && !fullData) loadFull();
    }
</script>

<svelte:head><title>출석 통계 - 부평동부교회</title></svelte:head>

<!-- 공동체 선택 드롭다운 (주차별/추이/전체 공용) -->
{#snippet communitySelect(selected: number | 'all', onChange: (v: number | 'all') => void)}
    <select class="px-3 py-2 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium text-sm"
        value={selected}
        onchange={(e) => { const v = (e.currentTarget as HTMLSelectElement).value; onChange(v === 'all' ? 'all' : Number(v)); }}>
        <option value="all">전체 공동체</option>
        {#each communities as c}<option value={c.id}>{c.name}</option>{/each}
    </select>
{/snippet}

<!-- 공동체별 소그룹 표 (주차별=출석 / 전체=기록주차) -->
{#snippet communityTable(blocks: { community: Community; stat: CommStat | undefined; groups: GroupStat[] }[], mode: 'week' | 'full')}
    {#each blocks as cc}
        <div class="rounded-2xl border border-gray-100 bg-white overflow-hidden mb-3">
            <div class="flex items-center justify-between px-4 py-2.5 bg-primary-50">
                <span class="font-black text-primary-900">{cc.community.name}</span>
                <span class="text-xs font-bold text-primary-800">
                    {#if mode === 'week'}{cc.stat?.present ?? 0}/{cc.stat?.members ?? 0}명 · {cc.stat?.rate ?? 0}%{:else}{cc.stat?.members ?? 0}명 · {cc.stat?.rate ?? 0}%{/if}
                </span>
            </div>
            <div class="grid grid-cols-[1fr_auto_auto_auto] gap-2 px-4 py-1.5 bg-gray-50/70 text-[11px] font-bold text-gray-400">
                <span>소그룹</span><span class="text-right w-14">인원</span><span class="text-right w-16">{mode === 'week' ? '출석' : '기록주차'}</span><span class="text-right w-16">출석률</span>
            </div>
            {#each cc.groups as g}
                <div class="grid grid-cols-[1fr_auto_auto_auto] gap-2 px-4 py-2.5 border-t border-gray-50 items-center text-sm">
                    <span class="font-medium text-gray-800">{g.name}</span>
                    <span class="text-right w-14 text-gray-600">{g.members}</span>
                    <span class="text-right w-16 text-gray-600">{mode === 'week' ? g.present : (g.recorded ?? 0) + '주'}</span>
                    <span class="text-right w-16 font-bold {mode === 'week' && g.present === 0 ? 'text-gray-300' : 'text-primary-700'}">{g.rate}%</span>
                </div>
            {/each}
        </div>
    {/each}
{/snippet}

<div class="w-full max-w-7xl mx-auto px-6 sm:px-8 lg:px-12 py-10 sm:py-14">
    <h1 class="text-2xl sm:text-3xl font-black text-gray-900 mb-1">출석 통계 대시보드</h1>
    <p class="text-gray-500 mb-6 text-sm sm:text-base">공동체·소그룹 출석 현황을 다양한 기준으로 살펴봅니다.</p>

    <AttendanceNav canCheck={canManage} canViewStats={true} {canManage} />

    {#if loading}
        <div class="py-20 text-center text-gray-400">불러오는 중…</div>
    {:else if denied}
        <div class="py-20 text-center">
            <p class="text-gray-500 font-medium">접근 권한이 없습니다.</p>
            <p class="text-gray-400 text-sm mt-2">교역자 또는 관리자만 볼 수 있습니다.</p>
            <a href="/attendance" class="inline-block mt-6 px-6 py-2.5 rounded-full bg-primary-900 text-white font-bold text-sm">출석 체크로</a>
        </div>
    {:else}
        <!-- 보기 모드 -->
        <div class="flex gap-1 mb-6 bg-gray-100 rounded-2xl p-1 w-fit">
            <button onclick={() => switchView('week')} class="px-4 py-2 rounded-xl text-sm font-bold transition-colors {view === 'week' ? 'bg-white text-primary-800 shadow-sm' : 'text-gray-500 hover:text-gray-800'}">주차별</button>
            <button onclick={() => switchView('trend')} class="px-4 py-2 rounded-xl text-sm font-bold transition-colors {view === 'trend' ? 'bg-white text-primary-800 shadow-sm' : 'text-gray-500 hover:text-gray-800'}">추이</button>
            <button onclick={() => switchView('full')} class="px-4 py-2 rounded-xl text-sm font-bold transition-colors {view === 'full' ? 'bg-white text-primary-800 shadow-sm' : 'text-gray-500 hover:text-gray-800'}">전체 통계</button>
        </div>

        {#if errorMsg}
            <div class="mb-5 bg-red-50 border border-red-100 text-red-600 text-sm rounded-xl px-4 py-3">{errorMsg}</div>
        {/if}

        <!-- ===== 주차별 ===== -->
        {#if view === 'week'}
            {#if sessions.length === 0}
                <p class="py-16 text-center text-gray-400">아직 진행된 주차가 없습니다.</p>
            {:else}
            <div class="flex items-center gap-3 mb-5 flex-wrap">
                <label for="wk" class="text-sm font-bold text-gray-700">주차</label>
                <select id="wk" class="px-4 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium text-sm"
                    value={weekSessionId} onchange={(e) => { weekSessionId = Number((e.target as HTMLSelectElement).value); loadWeek(); }}>
                    {#each sessions as s, i}
                        <option value={s.id}>{fmtDate(s.session_date)}{i === 0 ? ' (최근)' : ''}</option>
                    {/each}
                </select>
                {#if weekBusy}<span class="text-xs text-gray-400">불러오는 중…</span>{/if}
            </div>

            {#if weekData}
                <div class="rounded-2xl bg-primary-900 text-white p-6 mb-6 flex items-center justify-between">
                    <div>
                        <div class="text-sm font-medium text-white/70">{fmtDate(weekData.session_date)} 출석</div>
                        <div class="text-4xl font-black mt-1">{weekData.overall.present}<span class="text-xl text-white/60">명</span></div>
                    </div>
                    <div class="text-right text-sm text-white/80">
                        <div>전체 인원 <span class="font-bold text-white">{weekData.overall.members}</span>명</div>
                        <div>출석률 <span class="font-bold text-white">{weekData.overall.rate}%</span></div>
                    </div>
                </div>

                <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-8">
                    {#each weekData.communities as c}
                        <div class="rounded-2xl bg-white border border-gray-100 p-5">
                            <div class="font-black text-gray-900 text-lg">{c.name}</div>
                            <div class="text-3xl font-black text-primary-700 mt-2">{c.rate}%</div>
                            <div class="text-xs text-gray-500 mt-2">{c.present}/{c.members}명</div>
                        </div>
                    {/each}
                </div>

                <div class="flex items-center justify-between mb-3 flex-wrap gap-2">
                    <h2 class="text-base font-black text-gray-900">소그룹별</h2>
                    {@render communitySelect(weekFilter, (v) => (weekFilter = v))}
                </div>
                {@render communityTable(weekByCommunity, 'week')}
                <p class="text-xs text-gray-400 mt-2">※ 출석률 0%(회색)는 해당 주차를 아직 입력하지 않은 그룹일 수 있습니다.</p>
            {:else if !weekBusy}
                <p class="py-10 text-center text-gray-400">표시할 데이터가 없습니다.</p>
            {/if}
            {/if}

        <!-- ===== 추이 ===== -->
        {:else if view === 'trend'}
            <div class="flex items-center gap-2 mb-5 flex-wrap">
                <div class="flex gap-1 bg-gray-100 rounded-xl p-1">
                    <button onclick={() => { if (trendMode !== 'weekly') { trendMode='weekly'; loadTrend(); } }} class="px-3 py-1.5 rounded-lg text-sm font-bold {trendMode==='weekly'?'bg-white text-primary-800 shadow-sm':'text-gray-500'}">주간</button>
                    <button onclick={() => { if (trendMode !== 'monthly') { trendMode='monthly'; loadTrend(); } }} class="px-3 py-1.5 rounded-lg text-sm font-bold {trendMode==='monthly'?'bg-white text-primary-800 shadow-sm':'text-gray-500'}">월별</button>
                </div>
                {@render communitySelect(trendCommunity, (v) => { trendCommunity = v; trendGroup = 'all'; loadTrend(); })}
                <select class="px-3 py-2 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium text-sm"
                    value={trendGroup} onchange={(e) => { const v=(e.target as HTMLSelectElement).value; trendGroup = v==='all'?'all':Number(v); loadTrend(); }}>
                    <option value="all">전체 소그룹</option>
                    {#each trendGroupOptions as g}<option value={g.id}>{g.name}</option>{/each}
                </select>
                {#if trendBusy}<span class="text-xs text-gray-400">불러오는 중…</span>{/if}
            </div>

            <h2 class="text-base font-black text-gray-900 mb-3">{trendScopeLabel} · {trendMode === 'weekly' ? '주간' : '월별'} 출석률 추이</h2>
            {#if trendData.length === 0}
                <p class="text-gray-400 text-sm">데이터가 없습니다.</p>
            {:else}
                <div class="rounded-2xl border border-gray-100 bg-white p-4 overflow-x-auto">
                    <div class="flex items-end gap-2 min-w-fit" style="height:200px">
                        {#each trendData as t}
                            <div class="flex flex-col items-center gap-1 w-12 shrink-0 justify-end">
                                <span class="text-[10px] font-bold text-gray-500">{t.rate}%</span>
                                <div class="w-7 bg-gray-100 rounded-t-md flex items-end" style="height:150px">
                                    <div class="w-full bg-primary-500 rounded-t-md transition-all" style="height:{Math.max(t.rate * 1.5, t.present ? 4 : 0)}px"></div>
                                </div>
                                <span class="text-[9px] text-gray-400 text-center leading-tight">{t.date ? shortDate(t.date) : monthLabel(t.ym ?? '')}</span>
                            </div>
                        {/each}
                    </div>
                </div>
                <div class="rounded-2xl border border-gray-100 bg-white divide-y divide-gray-50 mt-4">
                    {#each [...trendData].reverse() as t}
                        <div class="flex items-center justify-between px-4 py-2.5 text-sm">
                            <span class="font-medium text-gray-800">{t.date ? fmtDate(t.date) : monthLabel(t.ym ?? '')}</span>
                            <span class="text-gray-500">{t.present}/{t.members}명</span>
                            <span class="font-bold text-primary-700 w-14 text-right">{t.rate}%</span>
                        </div>
                    {/each}
                </div>
                <p class="text-xs text-gray-400 mt-2">※ 출석률은 그 기간에 출석을 <b>기록한 그룹</b>의 인원 기준입니다.</p>
            {/if}

        <!-- ===== 전체 통계 ===== -->
        {:else}
            <div class="flex items-center gap-3 mb-5 flex-wrap">
                {@render communitySelect(fullCommunity, (v) => { fullCommunity = v; loadFull(); })}
                <button onclick={loadFull} class="px-4 py-2 rounded-xl bg-gray-900 text-white font-bold text-sm hover:bg-gray-700">새로고침</button>
                {#if fullBusy}<span class="text-xs text-gray-400">집계 중…</span>{/if}
            </div>

            {#if fullData}
                <div class="rounded-2xl bg-primary-900 text-white p-6 mb-6 flex items-center justify-between">
                    <div>
                        <div class="text-sm font-medium text-white/70">전체 누적 출석률 (기록된 주차 기준)</div>
                        <div class="text-4xl font-black mt-1">{fullData.overall.rate}%</div>
                    </div>
                    <div class="text-right text-sm text-white/80">누적 출석 <span class="font-bold text-white">{fullData.overall.present}</span>건</div>
                </div>
                <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-8">
                    {#each fullData.communities as c}
                        <div class="rounded-2xl bg-white border border-gray-100 p-5">
                            <div class="font-black text-gray-900 text-lg">{c.name}</div>
                            <div class="text-3xl font-black text-primary-700 mt-2">{c.rate}%</div>
                            <div class="text-xs text-gray-500 mt-2">{c.members}명</div>
                        </div>
                    {/each}
                </div>
                <h2 class="text-base font-black text-gray-900 mb-3">소그룹별 누적</h2>
                {@render communityTable(fullByCommunity, 'full')}
            {:else if !fullBusy}
                <p class="text-gray-400 text-sm">전체 통계를 불러오려면 위 버튼을 누르세요.</p>
            {/if}
        {/if}
    {/if}
</div>
