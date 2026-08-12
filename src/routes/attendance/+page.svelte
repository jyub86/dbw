<script lang="ts">
    import { onMount } from 'svelte';
    import { goto } from '$app/navigation';
    import { supabaseBrowser } from '$lib/supabase-browser';
    import { loadAccess, fetchAll, todayISO, fmtDate, pct } from '$lib/attendance';
    import AttendanceNav from '$lib/components/AttendanceNav.svelte';

    type Community = { name: string; sort_order: number };
    type Group = { id: number; name: string; sort_order: number; communities: Community | null };
    type Member = {
        id: number;
        role: string;
        sort_order: number;
        user_id: string;
        custom_users: { name: string | null; office: string | null } | null;
    };
    type Session = { id: number; session_date: string; sort_order: number };

    let loading = $state(true);
    let errorMsg = $state('');
    let myId = $state('');
    let canManage = $state(false);
    let canViewStats = $state(false);

    let groups = $state<Group[]>([]);
    let selectedGroupId = $state<number | null>(null);

    let members = $state<Member[]>([]);
    let sessions = $state<Session[]>([]);
    let selectedSessionId = $state<number | null>(null);

    // present[`${sessionId}:${memberId}`] = true
    let present = $state<Record<string, boolean>>({});
    // notes[`${memberId}:${sessionId}`] = text
    let notes = $state<Record<string, string>>({});
    let savingKey = $state('');
    // 소그룹 단위 기타 의견: groupNotes[sessionId] = text
    let groupNotes = $state<Record<number, string>>({});
    let savingGroupNote = $state(false);

    // 출석 체크 목록 정렬 (기본: 출석률 높은순)
    let sortBy = $state<'rate-desc' | 'rate-asc' | 'name'>('rate-desc');

    const today = todayISO();

    const selectedGroup = $derived(groups.find((g) => g.id === selectedGroupId) ?? null);
    const selectedSession = $derived(sessions.find((s) => s.id === selectedSessionId) ?? null);
    const pastSessions = $derived(sessions.filter((s) => s.session_date <= today));

    function isPresent(sid: number, mid: number) {
        return !!present[`${sid}:${mid}`];
    }
    function noteOf(mid: number, sid: number) {
        return notes[`${mid}:${sid}`] ?? '';
    }

    // ── 통계 ───────────────────────────────────────────────
    const weeklyStats = $derived(
        pastSessions.map((s) => {
            const cnt = members.filter((m) => isPresent(s.id, m.id)).length;
            const total = members.length || 1;
            return { session: s, count: cnt, total: members.length, rate: cnt / total };
        })
    );
    const memberStats = $derived(
        members.map((m) => {
            const cnt = pastSessions.filter((s) => isPresent(s.id, m.id)).length;
            const total = pastSessions.length || 1;
            return { member: m, count: cnt, total: pastSessions.length, rate: cnt / total };
        })
    );
    // 출석 체크용: 정렬된 멤버 목록
    const rateById = $derived(new Map(memberStats.map((ms) => [ms.member.id, ms.rate])));
    const sortedMembers = $derived(
        [...members].sort((a, b) => {
            if (sortBy === 'name')
                return (a.custom_users?.name ?? '').localeCompare(b.custom_users?.name ?? '', 'ko');
            if (sortBy === 'rate-asc')
                return (rateById.get(a.id) ?? 0) - (rateById.get(b.id) ?? 0) || a.sort_order - b.sort_order;
            // 기본: 출석률 높은순
            return (rateById.get(b.id) ?? 0) - (rateById.get(a.id) ?? 0) || a.sort_order - b.sort_order;
        })
    );
    // 인원별 특이사항 모아보기 (주차순)
    const noteEntries = $derived(
        members
            .map((m) => ({
                member: m,
                items: sessions
                    .filter((s) => notes[`${m.id}:${s.id}`])
                    .map((s) => ({ date: s.session_date, text: notes[`${m.id}:${s.id}`] }))
                    .reverse() // 최근 주차가 위로
            }))
            .filter((x) => x.items.length > 0)
    );
    // 기타 의견 모아보기 (최근 주차가 위로)
    const groupNoteEntries = $derived(
        sessions
            .filter((s) => groupNotes[s.id])
            .map((s) => ({ date: s.session_date, text: groupNotes[s.id] }))
            .reverse()
    );
    const overallRate = $derived(
        (() => {
            const denom = members.length * pastSessions.length;
            if (!denom) return 0;
            const num = weeklyStats.reduce((a, w) => a + w.count, 0);
            return num / denom;
        })()
    );

    onMount(async () => {
        const { hasSession, access } = await loadAccess();
        if (!hasSession) {
            goto('/login');
            return;
        }
        if (!access) {
            errorMsg = '사용자 정보를 찾을 수 없습니다.';
            loading = false;
            return;
        }
        myId = access.userId;
        canManage = access.canManage;
        canViewStats = access.canViewStats;

        // RLS: 리더는 본인 소그룹, 교역자/관리자는 전체
        const { data: gs, error } = await supabaseBrowser
            .from('small_groups')
            .select('id, name, sort_order, communities(name, sort_order)')
            .eq('active', true)
            .order('sort_order');
        if (error) {
            errorMsg = '소그룹을 불러오지 못했습니다.';
            loading = false;
            return;
        }
        groups = (gs ?? []) as unknown as Group[];
        // 공동체 순 → 소그룹 순 정렬
        groups.sort(
            (a, b) =>
                (a.communities?.sort_order ?? 0) - (b.communities?.sort_order ?? 0) ||
                a.sort_order - b.sort_order
        );

        if (groups.length === 0) {
            // 소그룹이 없지만 통계 열람 권한이 있으면 대시보드로 (통계 열람 전용 사용자)
            if (canViewStats) {
                goto('/attendance/dashboard');
                return;
            }
            loading = false;
            return;
        }
        await selectGroup(groups[0].id);
        loading = false;
    });

    async function selectGroup(gid: number) {
        selectedGroupId = gid;
        members = [];
        sessions = [];
        present = {};
        notes = {};
        groupNotes = {};

        const [{ data: mem }, { data: sess }] = await Promise.all([
            supabaseBrowser
                .from('small_group_members')
                .select('id, role, sort_order, user_id, custom_users(name, office)')
                .eq('small_group_id', gid)
                .eq('active', true)
                .order('sort_order'),
            supabaseBrowser
                .from('attendance_sessions')
                .select('id, session_date, sort_order')
                .eq('active', true)
                .order('sort_order')
        ]);
        members = (mem ?? []) as unknown as Member[];
        sessions = (sess ?? []) as unknown as Session[];

        // 기본 선택 = 오늘 이전의 가장 최근 주차
        const past = sessions.filter((s) => s.session_date <= today);
        selectedSessionId = (past.length ? past[past.length - 1] : sessions[0])?.id ?? null;

        const [recs, { data: ns }, { data: gns }] = await Promise.all([
            fetchAll<{ session_id: number; member_id: number; present: boolean }>((f, t) =>
                supabaseBrowser
                    .from('attendance_records')
                    .select('session_id, member_id, present')
                    .eq('small_group_id', gid)
                    .order('id')
                    .range(f, t)
            ),
            supabaseBrowser
                .from('member_notes')
                .select('member_id, session_id, note')
                .eq('small_group_id', gid),
            supabaseBrowser
                .from('group_session_notes')
                .select('session_id, note')
                .eq('small_group_id', gid)
        ]);
        const p: Record<string, boolean> = {};
        for (const r of recs) if (r.present) p[`${r.session_id}:${r.member_id}`] = true;
        present = p;
        const nm: Record<string, string> = {};
        for (const n of ns ?? []) if (n.note) nm[`${n.member_id}:${n.session_id}`] = n.note;
        notes = nm;
        const gn: Record<number, string> = {};
        for (const g of gns ?? []) if (g.note) gn[g.session_id] = g.note;
        groupNotes = gn;
    }

    async function toggleAttendance(mid: number) {
        if (!selectedSessionId || !selectedGroupId) return;
        const sid = selectedSessionId;
        const key = `${sid}:${mid}`;
        const next = !present[key];
        // 낙관적 업데이트
        present = { ...present, [key]: next };
        if (next) {
            const { error } = await supabaseBrowser.from('attendance_records').upsert(
                { session_id: sid, small_group_id: selectedGroupId, member_id: mid, present: true, recorded_by: myId },
                { onConflict: 'session_id,member_id' }
            );
            if (error) revert(key, false);
        } else {
            const { error } = await supabaseBrowser
                .from('attendance_records')
                .delete()
                .eq('session_id', sid)
                .eq('member_id', mid);
            if (error) revert(key, true);
        }
    }
    function revert(key: string, val: boolean) {
        present = { ...present, [key]: val };
        errorMsg = '저장에 실패했습니다. 다시 시도해주세요.';
    }

    async function saveNote(mid: number, value: string) {
        if (!selectedSessionId || !selectedGroupId) return;
        const sid = selectedSessionId;
        const key = `${mid}:${sid}`;
        const text = value.trim();
        savingKey = key;
        if (text) {
            await supabaseBrowser.from('member_notes').upsert(
                { session_id: sid, small_group_id: selectedGroupId, member_id: mid, note: text, created_by: myId },
                { onConflict: 'member_id,session_id' }
            );
            notes = { ...notes, [key]: text };
        } else {
            await supabaseBrowser.from('member_notes').delete().eq('member_id', mid).eq('session_id', sid);
            const { [key]: _drop, ...rest } = notes;
            notes = rest;
        }
        savingKey = '';
    }

    async function saveGroupNote(value: string) {
        if (!selectedSessionId || !selectedGroupId) return;
        const sid = selectedSessionId;
        const text = value.trim();
        savingGroupNote = true;
        if (text) {
            await supabaseBrowser.from('group_session_notes').upsert(
                { session_id: sid, small_group_id: selectedGroupId, note: text, created_by: myId },
                { onConflict: 'small_group_id,session_id' }
            );
            groupNotes = { ...groupNotes, [sid]: text };
        } else {
            await supabaseBrowser
                .from('group_session_notes')
                .delete()
                .eq('small_group_id', selectedGroupId)
                .eq('session_id', sid);
            const { [sid]: _drop, ...rest } = groupNotes;
            groupNotes = rest;
        }
        savingGroupNote = false;
    }

</script>

<svelte:head><title>출석부 - 부평동부교회</title></svelte:head>

<div class="w-full max-w-7xl mx-auto px-6 sm:px-8 lg:px-12 py-10 sm:py-14">
    <h1 class="text-2xl sm:text-3xl font-black text-gray-900 mb-1">소그룹 출석부</h1>
    <p class="text-gray-500 mb-6 text-sm sm:text-base">소그룹 리더가 출석과 특이사항을 기록합니다.</p>

    <AttendanceNav {canViewStats} {canManage} />

    {#if errorMsg}
        <div class="mb-6 bg-red-50 border border-red-100 text-red-600 text-sm rounded-xl px-4 py-3">{errorMsg}</div>
    {/if}

    {#if loading}
        <div class="py-20 text-center text-gray-400">불러오는 중…</div>
    {:else if groups.length === 0}
        <div class="py-20 text-center">
            <p class="text-gray-500 font-medium">출석부에 접근할 수 있는 소그룹이 없습니다.</p>
            <p class="text-gray-400 text-sm mt-2">소그룹 리더만 이용할 수 있습니다.</p>
            <a href="/" class="inline-block mt-6 px-6 py-2.5 rounded-full bg-primary-900 text-white font-bold text-sm">홈으로</a>
        </div>
    {:else}
        <!-- 소그룹 선택 -->
        {#if groups.length > 1}
            <div class="mb-6">
                <label for="grp" class="block text-sm font-bold text-gray-700 mb-2">소그룹</label>
                <select
                    id="grp"
                    class="w-full sm:w-72 px-4 py-3 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium"
                    value={selectedGroupId}
                    onchange={(e) => selectGroup(Number((e.target as HTMLSelectElement).value))}
                >
                    {#each groups as g}
                        <option value={g.id}>{g.communities?.name} · {g.name}</option>
                    {/each}
                </select>
            </div>
        {:else if selectedGroup}
            <div class="mb-6 inline-flex items-center gap-2 px-4 py-2 rounded-full bg-primary-50 text-primary-800 font-bold text-sm">
                {selectedGroup.communities?.name} · {selectedGroup.name}
            </div>
        {/if}

        <!-- 요약 -->
        <div class="grid grid-cols-3 gap-3 mb-8">
            <div class="rounded-2xl bg-white border border-gray-100 p-4 text-center">
                <div class="text-2xl font-black text-gray-900">{members.length}</div>
                <div class="text-xs text-gray-500 mt-1 font-medium">소그룹원</div>
            </div>
            <div class="rounded-2xl bg-white border border-gray-100 p-4 text-center">
                <div class="text-2xl font-black text-gray-900">{pastSessions.length}</div>
                <div class="text-xs text-gray-500 mt-1 font-medium">진행 주차</div>
            </div>
            <div class="rounded-2xl bg-white border border-gray-100 p-4 text-center">
                <div class="text-2xl font-black text-primary-700">{pct(overallRate)}%</div>
                <div class="text-xs text-gray-500 mt-1 font-medium">전체 출석률</div>
            </div>
        </div>

        <!-- 주차 선택 + 출석 체크 -->
        <section class="mb-10">
            <div class="flex items-center justify-between mb-4 gap-3 flex-wrap">
                <h2 class="text-lg font-black text-gray-900">출석 체크</h2>
                <div class="flex items-center gap-2 flex-wrap">
                    <select
                        aria-label="정렬"
                        class="px-4 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium text-sm"
                        bind:value={sortBy}
                    >
                        <option value="rate-desc">출석률 높은순</option>
                        <option value="rate-asc">출석률 낮은순</option>
                        <option value="name">이름순</option>
                    </select>
                    <select
                        aria-label="주차 선택"
                        class="px-4 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium text-sm"
                        value={selectedSessionId}
                        onchange={(e) => (selectedSessionId = Number((e.target as HTMLSelectElement).value))}
                    >
                        {#each sessions as s}
                            <option value={s.id}>
                                {fmtDate(s.session_date)}{s.session_date > today ? ' (예정)' : ''}
                            </option>
                        {/each}
                    </select>
                </div>
            </div>

            {#if selectedSession}
                <div class="rounded-2xl border border-gray-100 overflow-hidden">
                    {#each sortedMembers as m, i (m.id)}
                        {@const checked = isPresent(selectedSession.id, m.id)}
                        {@const nkey = `${m.id}:${selectedSession.id}`}
                        <div class="flex items-center gap-3 px-4 py-3 {i % 2 ? 'bg-gray-50/50' : 'bg-white'} border-b border-gray-50 last:border-0">
                            <button
                                type="button"
                                onclick={() => toggleAttendance(m.id)}
                                aria-pressed={checked}
                                aria-label="{m.custom_users?.name} 출석"
                                class="shrink-0 w-7 h-7 rounded-lg border-2 flex items-center justify-center transition-colors
                                {checked ? 'bg-primary-600 border-primary-600 text-white' : 'border-gray-300 text-transparent hover:border-primary-400'}"
                            >
                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7"/></svg>
                            </button>
                            <div class="shrink-0 w-24 sm:w-28">
                                <span class="font-bold text-gray-900">{m.custom_users?.name}</span>
                                {#if m.role === 'leader'}<span class="ml-1 text-[10px] font-bold text-primary-700 align-middle">리더</span>{/if}
                                <div class="text-[11px] text-gray-400">
                                    {m.custom_users?.office ?? ''}<span class="text-gray-300"> · 출석 {pct(rateById.get(m.id) ?? 0)}%</span>
                                </div>
                            </div>
                            <input
                                type="text"
                                placeholder="특이사항 (이 주차)"
                                value={noteOf(m.id, selectedSession.id)}
                                onchange={(e) => saveNote(m.id, (e.target as HTMLInputElement).value)}
                                class="flex-1 min-w-0 px-3 py-2 rounded-lg border border-gray-200 text-sm focus:outline-none focus:border-primary-500 bg-white"
                            />
                            {#if savingKey === nkey}<span class="text-[11px] text-gray-400 shrink-0">저장중…</span>{/if}
                        </div>
                    {/each}
                </div>
                <p class="text-xs text-gray-400 mt-2">체크 = 출석. 특이사항은 입력 후 칸을 벗어나면 저장됩니다.</p>

                <!-- 기타 의견 (소그룹 단위, 이 주차) -->
                <div class="mt-5">
                    <label for="gnote" class="flex items-center gap-2 text-sm font-bold text-gray-700 mb-2">
                        기타 의견 <span class="text-gray-400 font-normal">— 이 주차 소그룹에서 나온 의견</span>
                        {#if savingGroupNote}<span class="text-[11px] text-gray-400 font-normal">저장중…</span>{/if}
                    </label>
                    <textarea
                        id="gnote"
                        rows="3"
                        placeholder="이번 주 소그룹에서 나온 의견·건의사항을 적어주세요"
                        value={groupNotes[selectedSession.id] ?? ''}
                        onchange={(e) => saveGroupNote((e.target as HTMLTextAreaElement).value)}
                        class="w-full px-3 py-2.5 rounded-xl border border-gray-200 text-sm focus:outline-none focus:border-primary-500 resize-none leading-relaxed"
                    ></textarea>
                </div>
            {/if}
        </section>

        <!-- 특이사항 모아보기 -->
        <section class="mb-10">
            <h2 class="text-lg font-black text-gray-900 mb-4">특이사항 모아보기</h2>
            {#if noteEntries.length === 0}
                <p class="text-gray-400 text-sm">기록된 특이사항이 없습니다.</p>
            {:else}
                <div class="space-y-3">
                    {#each noteEntries as ne}
                        <div class="rounded-2xl border border-gray-100 bg-white p-4">
                            <div class="flex items-center gap-2 mb-2">
                                <span class="font-bold text-gray-900">{ne.member.custom_users?.name}</span>
                                {#if ne.member.role === 'leader'}<span class="text-[10px] font-bold text-primary-700">리더</span>{/if}
                                <span class="text-[11px] text-gray-400">{ne.member.custom_users?.office ?? ''}</span>
                                <span class="ml-auto text-[11px] text-gray-400">{ne.items.length}건</span>
                            </div>
                            <ul class="space-y-1.5">
                                {#each ne.items as it}
                                    <li class="flex gap-2 text-sm">
                                        <span class="shrink-0 text-xs font-bold text-primary-700 w-16">{fmtDate(it.date)}</span>
                                        <span class="text-gray-700 whitespace-pre-wrap">{it.text}</span>
                                    </li>
                                {/each}
                            </ul>
                        </div>
                    {/each}
                </div>
            {/if}
        </section>

        <!-- 기타 의견 모아보기 -->
        <section class="mb-10">
            <h2 class="text-lg font-black text-gray-900 mb-4">기타 의견 모아보기</h2>
            {#if groupNoteEntries.length === 0}
                <p class="text-gray-400 text-sm">기록된 기타 의견이 없습니다.</p>
            {:else}
                <div class="space-y-2">
                    {#each groupNoteEntries as ge}
                        <div class="rounded-2xl border border-gray-100 bg-white p-4">
                            <div class="text-xs font-bold text-primary-700 mb-1">{fmtDate(ge.date)}</div>
                            <p class="text-sm text-gray-700 whitespace-pre-wrap">{ge.text}</p>
                        </div>
                    {/each}
                </div>
            {/if}
        </section>

        <!-- 통계: 주차별 출석률 -->
        <section class="mb-10">
            <h2 class="text-lg font-black text-gray-900 mb-4">주차별 출석률</h2>
            {#if weeklyStats.length === 0}
                <p class="text-gray-400 text-sm">아직 진행된 주차가 없습니다.</p>
            {:else}
                <div class="rounded-2xl border border-gray-100 bg-white p-4 overflow-x-auto">
                    <div class="flex items-end gap-2 h-44 min-w-fit">
                        {#each weeklyStats as w}
                            <div class="flex flex-col items-center gap-1 w-10 shrink-0">
                                <span class="text-[10px] font-bold text-gray-500">{pct(w.rate)}%</span>
                                <div class="w-6 bg-gray-100 rounded-t-md flex items-end" style="height:120px">
                                    <div class="w-full bg-primary-500 rounded-t-md transition-all" style="height:{Math.max(w.rate * 120, w.count ? 4 : 0)}px"></div>
                                </div>
                                <span class="text-[9px] text-gray-400 text-center leading-tight">{w.session.session_date.slice(5).replace('-', '/')}</span>
                            </div>
                        {/each}
                    </div>
                </div>
            {/if}
        </section>

        <!-- 통계: 소그룹원별 출석 -->
        <section>
            <h2 class="text-lg font-black text-gray-900 mb-4">소그룹원별 출석</h2>
            <div class="rounded-2xl border border-gray-100 bg-white divide-y divide-gray-50">
                {#each memberStats as ms}
                    <div class="flex items-center gap-3 px-4 py-2.5">
                        <span class="w-24 sm:w-28 shrink-0 font-medium text-gray-800 text-sm truncate">{ms.member.custom_users?.name}</span>
                        <div class="flex-1 h-3 bg-gray-100 rounded-full overflow-hidden">
                            <div class="h-full bg-primary-500 rounded-full" style="width:{pct(ms.rate)}%"></div>
                        </div>
                        <span class="shrink-0 text-xs font-bold text-gray-600 w-20 text-right">{ms.count}/{ms.total}회 ({pct(ms.rate)}%)</span>
                    </div>
                {/each}
            </div>
        </section>
    {/if}
</div>
