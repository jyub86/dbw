<script lang="ts">
    import { onMount } from 'svelte';
    import { goto } from '$app/navigation';
    import { supabaseBrowser } from '$lib/supabase-browser';
    import { loadAccess } from '$lib/attendance';
    import AttendanceNav from '$lib/components/AttendanceNav.svelte';

    type Community = { name: string; sort_order: number };
    type Group = { id: number; name: string; sort_order: number; communities: Community | null };
    type Member = {
        id: number;
        role: string;
        sort_order: number;
        active: boolean;
        user_id: string;
        custom_users: { name: string | null; office: string | null; phone: string | null } | null;
    };
    type Profile = { id: string; name: string | null; office: string | null; phone: string | null; active?: boolean };
    type Manager = { user_id: string; note: string | null; custom_users: { name: string | null; office: string | null } | null };

    let loading = $state(true);
    let denied = $state(false);
    let isAdmin = $state(false);
    let msg = $state('');

    let groups = $state<Group[]>([]);
    let selectedGroupId = $state<number | null>(null);
    let members = $state<Member[]>([]);

    const selectedGroup = $derived(groups.find((g) => g.id === selectedGroupId) ?? null);

    // 프로필 검색(피커)
    let pickerOpen = $state(false);
    let pickerMode = $state<'add' | 'replace'>('add');
    let pickerTarget = $state<number | null>(null); // replace 대상 member.id
    let pickerQuery = $state('');
    let pickerResults = $state<Profile[]>([]);
    // 새 프로필 생성 시 고르는 구분(custom_users.office). DB 제약 없는 자유 텍스트.
    const OFFICES = ['성도', '집사', '시무집사', '권사', '장로', '목사', '전도사', '사모'];
    // 자녀돌봄 등 미성년 명단용 — 직분이 아니라 연령 구분이라 그룹을 나눠 표시한다.
    const CHILD_OFFICES = ['영아', '유치', '초등', '중등'];
    let newOffice = $state('성도');

    // 교역자 지정
    let managers = $state<Manager[]>([]);
    let mgrPickerOpen = $state(false);
    let mgrQuery = $state('');
    let mgrResults = $state<Profile[]>([]);

    // 통계 열람자 지정 (통계 대시보드만 열람)
    let statViewers = $state<Manager[]>([]);
    let svPickerOpen = $state(false);
    let svQuery = $state('');
    let svResults = $state<Profile[]>([]);

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
        isAdmin = access.isAdmin;

        const { data: gs } = await supabaseBrowser
            .from('small_groups')
            .select('id, name, sort_order, communities(name, sort_order)')
            .eq('active', true)
            .order('sort_order');
        groups = (gs ?? []) as unknown as Group[];
        groups.sort(
            (a, b) =>
                (a.communities?.sort_order ?? 0) - (b.communities?.sort_order ?? 0) ||
                a.sort_order - b.sort_order
        );
        if (groups.length) await selectGroup(groups[0].id);
        if (access.canManage) {
            await loadManagers();
            await loadStatViewers();
        }
        loading = false;
    });

    async function selectGroup(gid: number) {
        selectedGroupId = gid;
        await loadMembers();
    }
    async function loadMembers() {
        if (!selectedGroupId) return;
        const { data } = await supabaseBrowser
            .from('small_group_members')
            .select('id, role, sort_order, active, user_id, custom_users(name, office, phone)')
            .eq('small_group_id', selectedGroupId)
            .order('sort_order');
        members = (data ?? []) as unknown as Member[];
    }

    async function makeLeader(memberId: number) {
        if (!selectedGroupId) return;
        await supabaseBrowser
            .from('small_group_members')
            .update({ role: 'member' })
            .eq('small_group_id', selectedGroupId)
            .neq('id', memberId);
        await supabaseBrowser.from('small_group_members').update({ role: 'leader' }).eq('id', memberId);
        msg = '리더가 변경되었습니다.';
        await loadMembers();
    }
    async function setActive(memberId: number, active: boolean) {
        await supabaseBrowser.from('small_group_members').update({ active }).eq('id', memberId);
        await loadMembers();
    }

    // ── 프로필 피커 ───────────────────────────────
    function openAdd() {
        pickerMode = 'add';
        pickerTarget = null;
        pickerQuery = '';
        pickerResults = [];
        newOffice = '성도';
        pickerOpen = true;
    }
    function openReplace(memberId: number) {
        pickerMode = 'replace';
        pickerTarget = memberId;
        pickerQuery = '';
        pickerResults = [];
        pickerOpen = true;
    }
    async function searchProfiles(q: string, into: 'picker' | 'mgr' | 'sv') {
        const term = q.trim();
        if (term.length < 1) {
            if (into === 'picker') pickerResults = [];
            else if (into === 'mgr') mgrResults = [];
            else svResults = [];
            return;
        }
        // active 필터 없음: 미가입(placeholder, active=false) 프로필도 교체/추가 대상이 될 수 있음
        const { data } = await supabaseBrowser
            .from('custom_users')
            .select('id, name, office, phone, active')
            .ilike('name', `%${term}%`)
            .order('active', { ascending: false })
            .order('name')
            .limit(30);
        const rows = (data ?? []) as Profile[];
        if (into === 'picker') pickerResults = rows;
        else if (into === 'mgr') mgrResults = rows;
        else svResults = rows;
    }

    async function pickProfile(pid: string) {
        if (!selectedGroupId) return;
        msg = '';
        if (pickerMode === 'replace' && pickerTarget) {
            const { error } = await supabaseBrowser
                .from('small_group_members')
                .update({ user_id: pid })
                .eq('id', pickerTarget);
            msg = error ? '교체 실패: 이미 이 그룹에 있는 사람일 수 있습니다.' : '프로필이 교체되었습니다.';
        } else {
            const maxOrder = Math.max(0, ...members.map((m) => m.sort_order));
            const { error } = await supabaseBrowser
                .from('small_group_members')
                .insert({ small_group_id: selectedGroupId, user_id: pid, role: 'member', sort_order: maxOrder + 1 });
            msg = error ? '추가 실패: 이미 이 그룹에 있는 사람입니다.' : '구성원이 추가되었습니다.';
        }
        pickerOpen = false;
        await loadMembers();
    }

    async function createAndAdd() {
        if (!selectedGroupId) return;
        const name = pickerQuery.trim();
        if (!name) return;
        const { data, error } = await supabaseBrowser
            .from('custom_users')
            .insert({ name, office: newOffice, member: true, active: true })
            .select('id')
            .single();
        if (error || !data) {
            msg = '프로필 생성 실패';
            return;
        }
        await pickProfile(data.id);
    }

    // ── 교역자 지정 ───────────────────────────────
    async function loadManagers() {
        const { data } = await supabaseBrowser
            .from('attendance_managers')
            .select('user_id, note, custom_users(name, office)');
        managers = (data ?? []) as unknown as Manager[];
    }
    async function addManager(pid: string) {
        const { error } = await supabaseBrowser.from('attendance_managers').insert({ user_id: pid });
        msg = error ? '교역자 지정 실패 (관리자만 가능)' : '교역자로 지정되었습니다.';
        mgrPickerOpen = false;
        mgrQuery = '';
        mgrResults = [];
        await loadManagers();
    }
    async function removeManager(pid: string) {
        const { error } = await supabaseBrowser.from('attendance_managers').delete().eq('user_id', pid);
        if (error) msg = '해제 실패 (관리자만 가능)';
        await loadManagers();
    }

    // ── 통계 열람자 지정 ───────────────────────────────
    async function loadStatViewers() {
        const { data } = await supabaseBrowser
            .from('attendance_stat_viewers')
            .select('user_id, note, custom_users(name, office)');
        statViewers = (data ?? []) as unknown as Manager[];
    }
    async function addStatViewer(pid: string) {
        const { error } = await supabaseBrowser.from('attendance_stat_viewers').insert({ user_id: pid });
        msg = error ? '통계 열람자 지정 실패 (관리자만 가능)' : '통계 열람자로 지정되었습니다.';
        svPickerOpen = false;
        svQuery = '';
        svResults = [];
        await loadStatViewers();
    }
    async function removeStatViewer(pid: string) {
        const { error } = await supabaseBrowser.from('attendance_stat_viewers').delete().eq('user_id', pid);
        if (error) msg = '해제 실패 (관리자만 가능)';
        await loadStatViewers();
    }
</script>

<svelte:head><title>명단 관리 - 부평동부교회</title></svelte:head>

<div class="w-full max-w-7xl mx-auto px-6 sm:px-8 lg:px-12 py-10 sm:py-14">
    <h1 class="text-2xl sm:text-3xl font-black text-gray-900 mb-1">명단 관리</h1>
    <p class="text-gray-500 mb-6 text-sm sm:text-base">소그룹 구성원·리더와 교역자 권한을 관리합니다.</p>

    <AttendanceNav canCheck={true} canViewStats={true} canManage={true} />

    {#if msg}
        <div class="mb-5 bg-primary-50 border border-primary-100 text-primary-800 text-sm rounded-xl px-4 py-3">{msg}</div>
    {/if}

    {#if loading}
        <div class="py-20 text-center text-gray-400">불러오는 중…</div>
    {:else if denied}
        <div class="py-20 text-center">
            <p class="text-gray-500 font-medium">접근 권한이 없습니다.</p>
            <a href="/attendance" class="inline-block mt-6 px-6 py-2.5 rounded-full bg-primary-900 text-white font-bold text-sm">출석 체크로</a>
        </div>
    {:else}
        <!-- 그룹 선택 -->
        <div class="mb-6 flex items-end gap-3 flex-wrap">
            <div>
                <label for="g" class="block text-sm font-bold text-gray-700 mb-2">소그룹</label>
                <select id="g" class="px-4 py-3 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium"
                    value={selectedGroupId} onchange={(e) => selectGroup(Number((e.target as HTMLSelectElement).value))}>
                    {#each groups as g}<option value={g.id}>{g.communities?.name} · {g.name}</option>{/each}
                </select>
            </div>
            <button type="button" onclick={openAdd}
                class="px-5 py-3 rounded-xl bg-primary-900 text-white font-bold text-sm hover:bg-primary-800">+ 구성원 추가</button>
        </div>

        <!-- 구성원 목록 -->
        <div class="rounded-2xl border border-gray-100 overflow-hidden mb-12">
            {#each members as m, i}
                <div class="flex items-center gap-3 px-4 py-3 {m.active ? '' : 'bg-gray-50 opacity-60'} border-b border-gray-50 last:border-0">
                    <span class="w-6 text-xs text-gray-400 shrink-0">{i + 1}</span>
                    <div class="flex-1 min-w-0">
                        <span class="font-bold text-gray-900">{m.custom_users?.name}</span>
                        {#if m.role === 'leader'}<span class="ml-1.5 text-[10px] font-bold text-white bg-primary-600 px-1.5 py-0.5 rounded">리더</span>{/if}
                        {#if !m.active}<span class="ml-1.5 text-[10px] font-bold text-gray-500 bg-gray-200 px-1.5 py-0.5 rounded">제외됨</span>{/if}
                        <div class="text-[11px] text-gray-400">{m.custom_users?.office ?? ''} · {m.custom_users?.phone || '번호없음'}</div>
                    </div>
                    <div class="flex items-center gap-1.5 shrink-0">
                        {#if m.role !== 'leader' && m.active}
                            <button type="button" onclick={() => makeLeader(m.id)} class="px-2.5 py-1.5 rounded-lg text-xs font-bold border border-gray-200 text-gray-600 hover:border-primary-400 hover:text-primary-700">리더지정</button>
                        {/if}
                        <button type="button" onclick={() => openReplace(m.id)} class="px-2.5 py-1.5 rounded-lg text-xs font-bold border border-gray-200 text-gray-600 hover:border-primary-400 hover:text-primary-700">프로필교체</button>
                        {#if m.active}
                            <button type="button" onclick={() => setActive(m.id, false)} class="px-2.5 py-1.5 rounded-lg text-xs font-bold border border-red-200 text-red-500 hover:bg-red-50">제외</button>
                        {:else}
                            <button type="button" onclick={() => setActive(m.id, true)} class="px-2.5 py-1.5 rounded-lg text-xs font-bold border border-gray-200 text-gray-600 hover:border-primary-400">복귀</button>
                        {/if}
                    </div>
                </div>
            {/each}
        </div>

        <!-- 교역자(목사) 지정 -->
        <section>
            <div class="flex items-center justify-between mb-3">
                <h2 class="text-lg font-black text-gray-900">교역자(목사) 지정</h2>
                {#if isAdmin}
                    <button type="button" onclick={() => { mgrPickerOpen = !mgrPickerOpen; mgrQuery=''; mgrResults=[]; }}
                        class="px-4 py-2 rounded-xl bg-gray-900 text-white font-bold text-sm hover:bg-gray-700">+ 교역자 추가</button>
                {/if}
            </div>
            <p class="text-xs text-gray-400 mb-3">지정된 교역자는 <b>모든 소그룹의 특이사항(메모)</b>까지 열람할 수 있습니다. {isAdmin ? '' : '(추가/해제는 관리자만 가능)'}</p>

            {#if mgrPickerOpen}
                <div class="rounded-2xl border border-gray-200 p-4 mb-4 bg-gray-50">
                    <input type="text" placeholder="이름으로 검색" bind:value={mgrQuery} oninput={() => searchProfiles(mgrQuery, 'mgr')}
                        class="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm focus:outline-none focus:border-primary-500 mb-2" />
                    <div class="max-h-56 overflow-y-auto divide-y divide-gray-100 bg-white rounded-lg">
                        {#each mgrResults as r}
                            <button type="button" onclick={() => addManager(r.id)} class="w-full text-left px-3 py-2 hover:bg-primary-50 text-sm flex justify-between">
                                <span class="font-medium">{r.name}{#if r.active === false}<span class="ml-1 text-[10px] text-gray-400 font-normal">(미가입)</span>{/if}</span>
                                <span class="text-gray-400 text-xs">{r.office} · {r.phone || '번호없음'}</span>
                            </button>
                        {/each}
                        {#if mgrQuery && mgrResults.length === 0}<div class="px-3 py-3 text-sm text-gray-400">검색 결과 없음</div>{/if}
                    </div>
                </div>
            {/if}

            <div class="rounded-2xl border border-gray-100 overflow-hidden">
                {#if managers.length === 0}
                    <div class="px-4 py-5 text-sm text-gray-400 text-center">지정된 교역자가 없습니다.</div>
                {/if}
                {#each managers as mg}
                    <div class="flex items-center justify-between px-4 py-3 border-b border-gray-50 last:border-0">
                        <div>
                            <span class="font-bold text-gray-900">{mg.custom_users?.name ?? '(이름없음)'}</span>
                            <span class="text-xs text-gray-400 ml-2">{mg.custom_users?.office ?? ''}{mg.note ? ` · ${mg.note}` : ''}</span>
                        </div>
                        {#if isAdmin}
                            <button type="button" onclick={() => removeManager(mg.user_id)} class="px-2.5 py-1.5 rounded-lg text-xs font-bold border border-red-200 text-red-500 hover:bg-red-50">해제</button>
                        {/if}
                    </div>
                {/each}
            </div>
        </section>

        <!-- 통계 열람자 지정 -->
        <section class="mt-12">
            <div class="flex items-center justify-between mb-3">
                <h2 class="text-lg font-black text-gray-900">통계 열람자 지정</h2>
                {#if isAdmin}
                    <button type="button" onclick={() => { svPickerOpen = !svPickerOpen; svQuery=''; svResults=[]; }}
                        class="px-4 py-2 rounded-xl bg-gray-900 text-white font-bold text-sm hover:bg-gray-700">+ 열람자 추가</button>
                {/if}
            </div>
            <p class="text-xs text-gray-400 mb-3">지정된 열람자는 <b>소그룹 통계 대시보드만</b> 볼 수 있습니다. 출석 체크·명단·특이사항(메모)은 볼 수 없습니다. {isAdmin ? '' : '(추가/해제는 관리자만 가능)'}</p>

            {#if svPickerOpen}
                <div class="rounded-2xl border border-gray-200 p-4 mb-4 bg-gray-50">
                    <input type="text" placeholder="이름으로 검색" bind:value={svQuery} oninput={() => searchProfiles(svQuery, 'sv')}
                        class="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm focus:outline-none focus:border-primary-500 mb-2" />
                    <div class="max-h-56 overflow-y-auto divide-y divide-gray-100 bg-white rounded-lg">
                        {#each svResults as r}
                            <button type="button" onclick={() => addStatViewer(r.id)} class="w-full text-left px-3 py-2 hover:bg-primary-50 text-sm flex justify-between">
                                <span class="font-medium">{r.name}{#if r.active === false}<span class="ml-1 text-[10px] text-gray-400 font-normal">(미가입)</span>{/if}</span>
                                <span class="text-gray-400 text-xs">{r.office} · {r.phone || '번호없음'}</span>
                            </button>
                        {/each}
                        {#if svQuery && svResults.length === 0}<div class="px-3 py-3 text-sm text-gray-400">검색 결과 없음</div>{/if}
                    </div>
                </div>
            {/if}

            <div class="rounded-2xl border border-gray-100 overflow-hidden">
                {#if statViewers.length === 0}
                    <div class="px-4 py-5 text-sm text-gray-400 text-center">지정된 통계 열람자가 없습니다.</div>
                {/if}
                {#each statViewers as sv}
                    <div class="flex items-center justify-between px-4 py-3 border-b border-gray-50 last:border-0">
                        <div>
                            <span class="font-bold text-gray-900">{sv.custom_users?.name ?? '(이름없음)'}</span>
                            <span class="text-xs text-gray-400 ml-2">{sv.custom_users?.office ?? ''}{sv.note ? ` · ${sv.note}` : ''}</span>
                        </div>
                        {#if isAdmin}
                            <button type="button" onclick={() => removeStatViewer(sv.user_id)} class="px-2.5 py-1.5 rounded-lg text-xs font-bold border border-red-200 text-red-500 hover:bg-red-50">해제</button>
                        {/if}
                    </div>
                {/each}
            </div>
        </section>
    {/if}
</div>

<!-- 구성원 추가/교체 피커 모달 -->
{#if pickerOpen}
    <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40" role="presentation" onclick={() => (pickerOpen = false)}>
        <div class="bg-white rounded-3xl shadow-xl w-full max-w-md p-6" role="dialog" tabindex="-1" onclick={(e) => e.stopPropagation()} onkeydown={() => {}}>
            <h3 class="text-lg font-black text-gray-900 mb-1">{pickerMode === 'replace' ? '프로필 교체' : '구성원 추가'}</h3>
            <p class="text-xs text-gray-400 mb-4">
                {pickerMode === 'replace' ? '이 자리를 다른 사람으로 교체합니다 (출석·메모 기록은 유지됩니다).' : `${selectedGroup?.name}에 추가할 사람을 검색하세요.`}
            </p>
            <input type="text" placeholder="이름으로 검색" bind:value={pickerQuery} oninput={() => searchProfiles(pickerQuery, 'picker')}
                class="w-full px-3 py-2.5 rounded-xl border-2 border-gray-200 text-sm focus:outline-none focus:border-primary-500 mb-3" />
            <div class="max-h-64 overflow-y-auto divide-y divide-gray-100 border border-gray-100 rounded-xl">
                {#each pickerResults as r}
                    <button type="button" onclick={() => pickProfile(r.id)} class="w-full text-left px-3 py-2.5 hover:bg-primary-50 text-sm flex justify-between items-center">
                        <span class="font-medium text-gray-800">{r.name}{#if r.active === false}<span class="ml-1 text-[10px] text-gray-400 font-normal">(미가입)</span>{/if}</span>
                        <span class="text-gray-400 text-xs">{r.office} · {r.phone || '번호없음'}</span>
                    </button>
                {/each}
                {#if pickerQuery && pickerResults.length === 0}
                    <div class="px-3 py-3 text-sm text-gray-400">검색 결과 없음</div>
                {/if}
            </div>

            {#if pickerMode === 'add' && pickerQuery.trim()}
                <div class="mt-4 pt-4 border-t border-gray-100">
                    <p class="text-xs font-bold text-gray-600 mb-2">없으면 새 프로필 생성</p>
                    <div class="flex gap-2">
                        <select bind:value={newOffice} class="px-3 py-2 rounded-lg border border-gray-200 text-sm bg-white">
                            <optgroup label="직분">
                                {#each OFFICES as o}<option value={o}>{o}</option>{/each}
                            </optgroup>
                            <optgroup label="자녀">
                                {#each CHILD_OFFICES as o}<option value={o}>{o}</option>{/each}
                            </optgroup>
                        </select>
                        <button type="button" onclick={createAndAdd} class="flex-1 px-3 py-2 rounded-lg bg-primary-900 text-white text-sm font-bold hover:bg-primary-800">
                            "{pickerQuery.trim()}" 생성 후 추가
                        </button>
                    </div>
                </div>
            {/if}

            <button type="button" onclick={() => (pickerOpen = false)} class="mt-4 w-full py-2.5 rounded-xl border-2 border-gray-200 text-gray-600 font-bold text-sm hover:bg-gray-50">닫기</button>
        </div>
    </div>
{/if}
