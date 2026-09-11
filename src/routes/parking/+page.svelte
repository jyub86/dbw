<script lang="ts">
    import { onMount } from 'svelte';
    import { goto } from '$app/navigation';
    import { supabaseBrowser } from '$lib/supabase-browser';
    import { loadParkingAccess, normalizePlate } from '$lib/parking';

    // PostgREST 의 to-one 임베드는 런타임엔 객체 하나지만 생성 타입은 배열로 추론된다.
    type Embed<T> = T | T[] | null;
    type Owner = { name: string | null; office: string | null; phone: string | null };
    type Hit = { id: number; plate: string; memo: string | null; custom_users: Embed<Owner> };
    type Profile = { id: string; name: string | null; office: string | null; phone: string | null; active?: boolean };
    type Manager = { user_id: string; note: string | null; custom_users: Embed<Owner> };
    type Stats = {
        vehicles: number; people: number; multi: number;
        communities: { name: string; people: number }[];
    };

    const one = <T,>(v: Embed<T>): T | null => (Array.isArray(v) ? (v[0] ?? null) : (v ?? null));

    // 최소 2자 이상 입력해야 조회한다. 빈 검색으로 전체 명부가 쏟아지지 않도록.
    const MIN_Q = 2;

    let loading = $state(true);
    let denied = $state(false);
    let isAdmin = $state(false);
    let msg = $state('');
    let errorMsg = $state('');

    let view = $state<'search' | 'stats'>('search');

    let q = $state('');
    let hits = $state<Hit[]>([]);
    let searching = $state(false);
    let searched = $state(false);

    let stats = $state<Stats | null>(null);

    let managers = $state<Manager[]>([]);
    let mgrOpen = $state(false);
    let mgrQuery = $state('');
    let mgrResults = $state<Profile[]>([]);

    const qNorm = $derived(normalizePlate(q));

    let seq = 0;
    async function search() {
        const norm = qNorm;
        if (norm.length < MIN_Q) {
            hits = [];
            searched = false;
            return;
        }
        const mine = ++seq;
        searching = true;
        const { data, error } = await supabaseBrowser
            .from('member_vehicles')
            .select('id, plate, memo, custom_users(name, office, phone)')
            .ilike('plate_norm', `%${norm}%`)
            .limit(30);
        if (mine !== seq) return; // 늦게 온 옛 요청 폐기
        searching = false;
        searched = true;
        if (error) {
            errorMsg = '조회에 실패했습니다.';
            hits = [];
            return;
        }
        errorMsg = '';
        hits = (data ?? []) as unknown as Hit[];
    }

    let timer: ReturnType<typeof setTimeout> | undefined;
    function onInput() {
        clearTimeout(timer);
        timer = setTimeout(search, 300);
    }

    async function loadStats() {
        const { data, error } = await supabaseBrowser.rpc('parking_stats');
        if (error || data == null) {
            errorMsg = '현황을 불러오지 못했습니다.';
            return;
        }
        stats = data as Stats;
    }

    async function loadManagers() {
        const { data } = await supabaseBrowser
            .from('parking_managers')
            .select('user_id, note, custom_users(name, office, phone)');
        managers = (data ?? []) as unknown as Manager[];
    }

    onMount(async () => {
        const { hasSession, access } = await loadParkingAccess();
        if (!hasSession) return goto('/login');
        if (!access || !access.canManage) {
            denied = true;
            loading = false;
            return;
        }
        isAdmin = access.isAdmin;
        if (isAdmin) await loadManagers();
        loading = false;
    });

    function switchView(v: 'search' | 'stats') {
        view = v;
        errorMsg = '';
        if (v === 'stats' && !stats) loadStats();
    }

    async function searchProfiles(term: string) {
        const t = term.trim();
        if (!t) {
            mgrResults = [];
            return;
        }
        const { data } = await supabaseBrowser
            .from('custom_users')
            .select('id, name, office, phone, active')
            .ilike('name', `%${t}%`)
            .order('active', { ascending: false })
            .order('name')
            .limit(30);
        mgrResults = (data ?? []) as Profile[];
    }
    async function addManager(pid: string) {
        const { error } = await supabaseBrowser.from('parking_managers').insert({ user_id: pid });
        msg = error ? '담당자 지정 실패 (관리자만 가능)' : '주차 담당자로 지정했습니다.';
        mgrOpen = false;
        mgrQuery = '';
        mgrResults = [];
        await loadManagers();
    }
    async function removeManager(pid: string) {
        const { error } = await supabaseBrowser.from('parking_managers').delete().eq('user_id', pid);
        if (error) msg = '해제 실패 (관리자만 가능)';
        await loadManagers();
    }
</script>

<svelte:head><title>주차 관리 - 부평동부교회</title></svelte:head>

<div class="w-full max-w-7xl mx-auto px-6 sm:px-8 lg:px-12 py-10 sm:py-14">
    <h1 class="text-2xl sm:text-3xl font-black text-gray-900 mb-1">주차 관리</h1>
    <p class="text-gray-500 mb-6 text-sm sm:text-base">등록된 차량을 조회하고 주차 수요를 확인합니다.</p>

    {#if loading}
        <div class="py-20 text-center text-gray-400">불러오는 중…</div>
    {:else if denied}
        <div class="py-20 text-center">
            <p class="text-gray-500 font-medium">접근 권한이 없습니다.</p>
            <p class="text-gray-400 text-sm mt-2">주차 담당자 또는 관리자만 볼 수 있습니다.</p>
            <a href="/parking/my" class="inline-block mt-6 px-6 py-2.5 rounded-full bg-primary-900 text-white font-bold text-sm">내 차량 등록으로</a>
        </div>
    {:else}
        <div class="flex gap-1 mb-6 bg-gray-100 rounded-2xl p-1 w-fit">
            <button type="button" onclick={() => switchView('search')}
                class="px-4 py-2 rounded-xl text-sm font-bold transition-colors {view === 'search' ? 'bg-white text-primary-800 shadow-sm' : 'text-gray-500 hover:text-gray-800'}">차량 조회</button>
            <button type="button" onclick={() => switchView('stats')}
                class="px-4 py-2 rounded-xl text-sm font-bold transition-colors {view === 'stats' ? 'bg-white text-primary-800 shadow-sm' : 'text-gray-500 hover:text-gray-800'}">주차 현황</button>
        </div>

        {#if msg}
            <div class="mb-5 bg-primary-50 border border-primary-100 text-primary-800 text-sm rounded-xl px-4 py-3">{msg}</div>
        {/if}
        {#if errorMsg}
            <div class="mb-5 bg-red-50 border border-red-100 text-red-600 text-sm rounded-xl px-4 py-3">{errorMsg}</div>
        {/if}

        {#if view === 'search'}
            <div class="rounded-2xl border border-gray-100 bg-gray-50 px-4 py-4 mb-5">
                <label for="q" class="block text-xs font-bold text-gray-600 mb-1.5">차량번호 조회</label>
                <input id="q" type="text" bind:value={q} oninput={onInput} placeholder="번호 일부만 입력해도 됩니다 (예: 3456)"
                    class="w-full max-w-md px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium text-sm" />
                <p class="mt-2 text-xs text-gray-400">{MIN_Q}자 이상 입력하면 조회됩니다. 뒷자리만으로도 찾을 수 있습니다.</p>
            </div>

            {#if searching}
                <div class="py-10 text-center text-gray-400 text-sm">조회 중…</div>
            {:else if qNorm.length < MIN_Q}
                <div class="py-16 text-center text-gray-400 text-sm">조회할 번호를 입력하세요.</div>
            {:else if searched && hits.length === 0}
                <div class="py-16 text-center text-gray-400 text-sm">등록된 차량이 없습니다.</div>
            {:else}
                <p class="text-sm text-gray-500 mb-3"><b class="text-gray-900">{hits.length}</b>건</p>
                <div class="rounded-2xl border border-gray-200 overflow-hidden">
                    {#each hits as h (h.id)}
                        {@const o = one(h.custom_users)}
                        <div class="flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-3 border-b border-gray-50 last:border-0">
                            <span class="font-black text-gray-900 tracking-wide w-32">{h.plate}</span>
                            <span class="font-bold text-gray-800">{o?.name ?? '(이름없음)'}</span>
                            <span class="text-xs text-gray-400">{o?.office ?? ''}</span>
                            {#if h.memo}<span class="text-sm text-gray-500">{h.memo}</span>{/if}
                            {#if o?.phone}
                                <a href={`tel:${o.phone}`} class="ml-auto px-3 py-1.5 rounded-lg text-sm font-bold bg-primary-900 text-white hover:bg-primary-800">{o.phone}</a>
                            {:else}
                                <span class="ml-auto text-xs text-gray-400">번호없음</span>
                            {/if}
                        </div>
                    {/each}
                </div>
            {/if}
        {:else}
            <!-- 주차 현황 -->
            {#if !stats}
                <div class="py-16 text-center text-gray-400 text-sm">불러오는 중…</div>
            {:else}
                <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-8">
                    <div class="rounded-2xl bg-primary-900 text-white p-5">
                        <div class="text-sm text-white/70">등록 차량</div>
                        <div class="text-4xl font-black mt-1">{stats.vehicles}<span class="text-xl text-white/60">대</span></div>
                    </div>
                    <div class="rounded-2xl bg-white border border-gray-100 p-5">
                        <div class="text-sm text-gray-500">등록 인원</div>
                        <div class="text-4xl font-black text-primary-700 mt-1">{stats.people}<span class="text-xl text-gray-400">명</span></div>
                    </div>
                    <div class="rounded-2xl bg-white border border-gray-100 p-5">
                        <div class="text-sm text-gray-500">2대 이상</div>
                        <div class="text-4xl font-black text-gray-900 mt-1">{stats.multi}<span class="text-xl text-gray-400">명</span></div>
                    </div>
                </div>

                <h2 class="text-base font-black text-gray-900 mb-3">공동체별 등록 인원</h2>
                {#if stats.communities.length === 0}
                    <p class="text-gray-400 text-sm">소그룹에 속한 등록자가 없습니다.</p>
                {:else}
                    <div class="rounded-2xl border border-gray-200 overflow-hidden mb-3">
                        {#each stats.communities as c}
                            <div class="flex items-center justify-between px-4 py-3 border-b border-gray-50 last:border-0">
                                <span class="font-bold text-gray-800">{c.name}</span>
                                <span class="text-gray-600">{c.people}명</span>
                            </div>
                        {/each}
                    </div>
                {/if}
                <p class="text-xs text-gray-400">※ 소그룹에 속하지 않은 등록자는 공동체별 집계에 포함되지 않습니다.</p>
            {/if}
        {/if}

        <!-- 담당자 지정 (관리자만) -->
        {#if isAdmin}
            <section class="mt-14">
                <div class="flex items-center justify-between mb-3">
                    <h2 class="text-lg font-black text-gray-900">주차 담당자 지정</h2>
                    <button type="button" onclick={() => { mgrOpen = !mgrOpen; mgrQuery = ''; mgrResults = []; }}
                        class="px-4 py-2 rounded-xl bg-gray-900 text-white font-bold text-sm hover:bg-gray-700">+ 담당자 추가</button>
                </div>
                <p class="text-xs text-gray-400 mb-3">지정된 담당자는 <b>모든 교인의 차량번호와 연락처</b>를 조회할 수 있습니다. (추가/해제는 관리자만 가능)</p>

                {#if mgrOpen}
                    <div class="rounded-2xl border border-gray-200 p-4 mb-4 bg-gray-50">
                        <input type="text" placeholder="이름으로 검색" bind:value={mgrQuery} oninput={() => searchProfiles(mgrQuery)}
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
                        <div class="px-4 py-5 text-sm text-gray-400 text-center">지정된 담당자가 없습니다.</div>
                    {/if}
                    {#each managers as m}
                        {@const o = one(m.custom_users)}
                        <div class="flex items-center justify-between px-4 py-3 border-b border-gray-50 last:border-0">
                            <div>
                                <span class="font-bold text-gray-900">{o?.name ?? '(이름없음)'}</span>
                                <span class="text-xs text-gray-400 ml-2">{o?.office ?? ''}{m.note ? ` · ${m.note}` : ''}</span>
                            </div>
                            <button type="button" onclick={() => removeManager(m.user_id)}
                                class="px-2.5 py-1.5 rounded-lg text-xs font-bold border border-red-200 text-red-500 hover:bg-red-50">해제</button>
                        </div>
                    {/each}
                </div>
            </section>
        {/if}
    {/if}
</div>
