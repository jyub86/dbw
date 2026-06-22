<script lang="ts">
    import { onMount } from 'svelte';
    import { goto } from '$app/navigation';
    import { supabaseBrowser } from '$lib/supabase-browser';
    import { loadAccess, pct, todayISO, fetchAll } from '$lib/attendance';
    import AttendanceNav from '$lib/components/AttendanceNav.svelte';

    type Community = { id: number; name: string; sort_order: number };
    type Group = { id: number; name: string; community_id: number; sort_order: number };
    type Sess = { id: number; session_date: string; sort_order: number };

    let loading = $state(true);
    let denied = $state(false);

    let communities = $state<Community[]>([]);
    let groups = $state<Group[]>([]);
    let memberCount = $state<Record<number, number>>({}); // group_id -> active members
    let sessions = $state<Sess[]>([]);
    // present[`${session_id}:${group_id}`] = count
    let present = $state<Record<string, number>>({});

    const today = todayISO();
    const pastSessions = $derived(sessions.filter((s) => s.session_date <= today));

    function presentAt(sid: number, gid: number) {
        return present[`${sid}:${gid}`] ?? 0;
    }
    // 그 그룹이 실제로 기록한 주차 수 (1명 이상 출석 기록이 있는 주차)
    function groupRecordedCount(gid: number) {
        return pastSessions.filter((s) => presentAt(s.id, gid) > 0).length;
    }
    function groupPresentTotal(gid: number) {
        return pastSessions.reduce((a, s) => a + presentAt(s.id, gid), 0);
    }
    function groupRate(gid: number) {
        const denom = (memberCount[gid] ?? 0) * groupRecordedCount(gid);
        return denom ? groupPresentTotal(gid) / denom : 0;
    }
    // 그룹별 가장 최근에 "기록된" 주차의 출석률 (+ 날짜)
    function groupLast(gid: number): { date: string; rate: number } | null {
        for (let i = pastSessions.length - 1; i >= 0; i--) {
            const s = pastSessions[i];
            const c = presentAt(s.id, gid);
            if (c > 0) {
                const m = memberCount[gid] ?? 0;
                return { date: s.session_date, rate: m ? c / m : 0 };
            }
        }
        return null;
    }

    function aggRate(gs: Group[]) {
        let num = 0,
            den = 0;
        for (const g of gs) {
            num += groupPresentTotal(g.id);
            den += (memberCount[g.id] ?? 0) * groupRecordedCount(g.id);
        }
        return den ? num / den : 0;
    }

    const communityStats = $derived(
        communities.map((c) => {
            const gs = groups.filter((g) => g.community_id === c.id);
            const members = gs.reduce((a, g) => a + (memberCount[g.id] ?? 0), 0);
            return { community: c, groups: gs, members, rate: aggRate(gs) };
        })
    );

    const overall = $derived({
        members: groups.reduce((a, g) => a + (memberCount[g.id] ?? 0), 0),
        rate: aggRate(groups)
    });

    // 주차별 전체 출석률 (기록한 그룹의 인원만 분모로) — 기록 있는 주차만 표시
    const weekly = $derived(
        pastSessions
            .map((s) => {
                let cnt = 0,
                    participating = 0;
                for (const g of groups) {
                    const c = presentAt(s.id, g.id);
                    if (c > 0) {
                        cnt += c;
                        participating += memberCount[g.id] ?? 0;
                    }
                }
                return { session: s, count: cnt, rate: participating ? cnt / participating : 0 };
            })
            .filter((w) => w.count > 0)
    );

    onMount(async () => {
        const { hasSession, access } = await loadAccess();
        if (!hasSession) {
            goto('/login');
            return;
        }
        if (!access || !access.canManage) {
            denied = true;
            loading = false;
            return;
        }

        const [{ data: comms }, { data: gs }, { data: mem }, { data: sess }] = await Promise.all([
            supabaseBrowser.from('communities').select('id,name,sort_order').order('sort_order'),
            supabaseBrowser
                .from('small_groups')
                .select('id,name,community_id,sort_order')
                .eq('active', true)
                .order('sort_order'),
            supabaseBrowser.from('small_group_members').select('small_group_id').eq('active', true),
            supabaseBrowser
                .from('attendance_sessions')
                .select('id,session_date,sort_order')
                .eq('active', true)
                .order('sort_order')
        ]);
        // 출석기록은 1000행 제한이 있어 끝까지 페이지네이션
        const recs = await fetchAll<{ session_id: number; small_group_id: number; present: boolean }>(
            (f, t) =>
                supabaseBrowser
                    .from('attendance_records')
                    .select('session_id,small_group_id,present')
                    .order('id')
                    .range(f, t)
        );

        communities = (comms ?? []) as Community[];
        groups = (gs ?? []) as Group[];
        sessions = (sess ?? []) as Sess[];

        const mc: Record<number, number> = {};
        for (const m of mem ?? []) mc[m.small_group_id] = (mc[m.small_group_id] ?? 0) + 1;
        memberCount = mc;

        const p: Record<string, number> = {};
        for (const r of recs ?? []) {
            if (!r.present) continue;
            const k = `${r.session_id}:${r.small_group_id}`;
            p[k] = (p[k] ?? 0) + 1;
        }
        present = p;

        loading = false;
    });
</script>

<svelte:head><title>출석 통계 - 부평동부교회</title></svelte:head>

<div class="w-full max-w-5xl mx-auto px-5 sm:px-8 py-10 sm:py-14">
    <h1 class="text-2xl sm:text-3xl font-black text-gray-900 mb-1">출석 통계 대시보드</h1>
    <p class="text-gray-500 mb-6 text-sm sm:text-base">전체 공동체·소그룹 출석 현황입니다.</p>

    <AttendanceNav canManage={true} />

    {#if loading}
        <div class="py-20 text-center text-gray-400">불러오는 중…</div>
    {:else if denied}
        <div class="py-20 text-center">
            <p class="text-gray-500 font-medium">접근 권한이 없습니다.</p>
            <p class="text-gray-400 text-sm mt-2">교역자 또는 관리자만 볼 수 있습니다.</p>
            <a href="/attendance" class="inline-block mt-6 px-6 py-2.5 rounded-full bg-primary-900 text-white font-bold text-sm">출석 체크로</a>
        </div>
    {:else}
        <!-- 전체 요약 -->
        <div class="rounded-2xl bg-primary-900 text-white p-6 mb-6 flex items-center justify-between">
            <div>
                <div class="text-sm font-medium text-white/70">전체 출석률 (기록된 주차 기준)</div>
                <div class="text-4xl font-black mt-1">{pct(overall.rate)}%</div>
            </div>
            <div class="text-right text-sm text-white/80">
                <div>전체 인원 <span class="font-bold text-white">{overall.members}</span>명</div>
                <div>소그룹 <span class="font-bold text-white">{groups.length}</span>개</div>
            </div>
        </div>

        <!-- 공동체별 -->
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-10">
            {#each communityStats as cs}
                <div class="rounded-2xl bg-white border border-gray-100 p-5">
                    <div class="font-black text-gray-900 text-lg">{cs.community.name}</div>
                    <div class="text-3xl font-black text-primary-700 mt-2">{pct(cs.rate)}%</div>
                    <div class="text-xs text-gray-500 mt-2">{cs.groups.length}개 그룹 · {cs.members}명</div>
                </div>
            {/each}
        </div>

        <!-- 주차별 추이 -->
        <section class="mb-10">
            <h2 class="text-lg font-black text-gray-900 mb-4">주차별 전체 출석률</h2>
            {#if weekly.length === 0}
                <p class="text-gray-400 text-sm">아직 진행된 주차가 없습니다.</p>
            {:else}
                <div class="rounded-2xl border border-gray-100 bg-white p-4 overflow-x-auto">
                    <div class="flex items-end gap-2 h-44 min-w-fit">
                        {#each weekly as w}
                            <div class="flex flex-col items-center gap-1 w-10 shrink-0">
                                <span class="text-[10px] font-bold text-gray-500">{pct(w.rate)}%</span>
                                <div class="w-6 bg-gray-100 rounded-t-md flex items-end" style="height:120px">
                                    <div class="w-full bg-primary-500 rounded-t-md" style="height:{Math.max(w.rate * 120, w.count ? 4 : 0)}px"></div>
                                </div>
                                <span class="text-[9px] text-gray-400 text-center leading-tight">{w.session.session_date.slice(5).replace('-', '/')}</span>
                            </div>
                        {/each}
                    </div>
                </div>
            {/if}
        </section>

        <!-- 소그룹별 상세 -->
        {#each communityStats as cs}
            <section class="mb-8">
                <h2 class="text-base font-black text-gray-900 mb-3">{cs.community.name} <span class="text-gray-400 font-medium text-sm">· {cs.groups.length}개 그룹</span></h2>
                <div class="rounded-2xl border border-gray-100 bg-white overflow-hidden">
                    <div class="grid grid-cols-[1fr_auto_auto_auto] gap-2 px-4 py-2 bg-gray-50 text-[11px] font-bold text-gray-500">
                        <span>소그룹</span><span class="text-right w-14">인원</span><span class="text-right w-20">전체출석</span><span class="text-right w-24">최근주차</span>
                    </div>
                    {#each [...cs.groups].sort((a, b) => groupRate(b.id) - groupRate(a.id)) as g}
                        {@const gl = groupLast(g.id)}
                        <div class="grid grid-cols-[1fr_auto_auto_auto] gap-2 px-4 py-2.5 border-t border-gray-50 items-center text-sm">
                            <span class="font-medium text-gray-800">{g.name}</span>
                            <span class="text-right w-14 text-gray-600">{memberCount[g.id] ?? 0}</span>
                            <span class="text-right w-20 font-bold text-primary-700">{pct(groupRate(g.id))}%</span>
                            <span class="text-right w-24 text-gray-600">
                                {#if gl}{pct(gl.rate)}% <span class="text-[10px] text-gray-400">({gl.date.slice(5).replace('-', '/')})</span>{:else}-{/if}
                            </span>
                        </div>
                    {/each}
                </div>
            </section>
        {/each}
    {/if}
</div>
