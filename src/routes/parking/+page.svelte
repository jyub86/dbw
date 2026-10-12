<script lang="ts">
    import { onMount } from 'svelte';
    import { goto } from '$app/navigation';
    import { supabaseBrowser } from '$lib/supabase-browser';
    import { loadParkingAccess, normalizePlate, looksLikePlate } from '$lib/parking';
    import { todayISO } from '$lib/attendance';

    // PostgREST 의 to-one 임베드는 런타임엔 객체 하나지만 생성 타입은 배열로 추론된다.
    type Embed<T> = T | T[] | null;
    type Owner = { name: string | null; office: string | null; phone: string | null };
    type Hit = {
        id: number; plate: string; memo: string | null; consent_on: string | null; consent_method: string | null; created_at: string;
        custom_users: Embed<Owner>;
        registered_by_user: Embed<{ name: string | null }>;   // 대리 등록자 (본인 등록이면 null)
    };
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
    let myId = $state('');
    let msg = $state('');
    let errorMsg = $state('');

    let view = $state<'search' | 'stats' | 'add'>('search');

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
            .select('id, plate, memo, consent_on, consent_method, created_at, custom_users!member_vehicles_user_id_fkey(name, office, phone), registered_by_user:custom_users!member_vehicles_registered_by_fkey(name)')
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
        myId = access.userId;
        if (isAdmin) await loadManagers();
        loading = false;
    });

    function switchView(v: 'search' | 'stats' | 'add') {
        view = v;
        errorMsg = '';
        msg = '';
        if (v === 'stats' && !stats) loadStats();
    }

    // 등록일 표시 — 오래 방치된 항목(차를 바꿨는데 그대로일 수 있다)을 눈에 띄게 한다.
    const STALE_DAYS = 365;
    const fmtDay = (iso: string) => (iso || '').slice(0, 10).replaceAll('-', '.');
    const daysSince = (iso: string) =>
        Math.floor((Date.now() - new Date(iso).getTime()) / 86400000);
    const isStale = (iso: string) => daysSince(iso) >= STALE_DAYS;
    const ageText = (iso: string) => {
        const d = daysSince(iso);
        return d >= 365 ? `${Math.floor(d / 365)}년 지남` : `${Math.floor(d / 30)}개월 지남`;
    };

    // ── 대리 등록 ────────────────────────────────
    // 앱 사용이 어려운 어르신 대신 등록한다. 남의 개인정보라 동의가 근거이고,
    // 누가·언제·어떤 방법으로 받았는지를 행에 함께 남긴다(DB CHECK 로도 강제된다).
    // 동의 방법은 서면만이 아니다 — 개인정보 보호법 시행령 제17조 제2항이 6가지를 허용하고
    // 2호가 "전화로 동의 내용을 알리고 동의의 의사표시를 확인하는 방법"이다.
    // 서면만 받게 하면 정작 앱을 못 쓰는 분을 대신 등록한다는 기능 목적이 막힌다.
    let addQuery = $state('');
    let addResults = $state<Profile[]>([]);
    let addTarget = $state<Profile | null>(null);
    let addPlate = $state('');
    let addMemo = $state('');
    let addConsentOn = $state(todayISO());
    let addConsentMethod = $state('전화');
    let addConfirmed = $state(false);
    let addBusy = $state(false);

    const addPlateNorm = $derived(normalizePlate(addPlate));
    const addWarn = $derived(addPlateNorm.length >= 4 && !looksLikePlate(addPlate));
    const canSubmitAdd = $derived(
        !!addTarget && addPlateNorm.length >= 4 && !!addConsentOn && !!addConsentMethod
            && addConfirmed && !addBusy
    );

    // custom_users 직접 조회는 쓸 수 없다 — 프로필 조회가 좁혀져 있어서(소그룹·게시글·본인 등)
    // 주차 담당자에겐 교인 대부분이 안 보인다(실측: 633명 중 117명). 정작 등록해 줘야 할
    // 어르신을 못 찾는다. 이 기능에 필요한 최소 필드만 여는 RPC 를 쓴다.
    async function searchAddTargets(term: string) {
        const t = term.trim();
        if (!t) { addResults = []; return; }
        const { data, error } = await supabaseBrowser.rpc('parking_search_members', { q: t });
        if (error) { errorMsg = '교인 검색에 실패했습니다.'; addResults = []; return; }
        addResults = (data ?? []) as Profile[];
    }
    function resetAdd() {
        addTarget = null; addQuery = ''; addResults = [];
        addPlate = ''; addMemo = ''; addConsentOn = todayISO();
        addConsentMethod = '전화'; addConfirmed = false;
    }
    async function submitAdd() {
        if (!canSubmitAdd || !addTarget) return;
        addBusy = true;
        msg = ''; errorMsg = '';
        const { error } = await supabaseBrowser.from('member_vehicles').insert({
            user_id: addTarget.id,
            plate: addPlate.trim(),
            memo: addMemo.trim() || null,
            registered_by: myId,
            consent_on: addConsentOn,
            consent_method: addConsentMethod
        });
        addBusy = false;
        if (error) {
            // 같은 사람 + 같은 번호는 unique(user_id, plate_norm) 로 막힌다.
            errorMsg = /duplicate|unique/i.test(error.message)
                ? `${addTarget.name} 님에게 이미 등록된 번호입니다.`
                : '등록 실패: ' + error.message;
            return;
        }
        msg = `${addTarget.name} 님의 차량 ${addPlate.trim()} 을(를) 대신 등록했습니다.`;
        resetAdd();
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
            <button type="button" onclick={() => switchView('add')}
                class="px-4 py-2 rounded-xl text-sm font-bold transition-colors {view === 'add' ? 'bg-white text-primary-800 shadow-sm' : 'text-gray-500 hover:text-gray-800'}">대리 등록</button>
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
                        {@const by = one(h.registered_by_user)}
                        <div class="flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-3 border-b border-gray-50 last:border-0">
                            <span class="font-black text-gray-900 tracking-wide w-32">{h.plate}</span>
                            <span class="font-bold text-gray-800">{o?.name ?? '(이름없음)'}</span>
                            <span class="text-xs text-gray-400">{o?.office ?? ''}</span>
                            {#if h.memo}<span class="text-sm text-gray-500">{h.memo}</span>{/if}
                            <span class="text-xs {isStale(h.created_at) ? 'font-bold text-amber-600' : 'text-gray-400'}">
                                {fmtDay(h.created_at)} 등록{#if isStale(h.created_at)} · {ageText(h.created_at)}{/if}
                            </span>
                            {#if by}
                                <span class="text-[11px] font-bold text-primary-700 bg-primary-50 px-1.5 py-0.5 rounded">
                                    대리 {by.name ?? ''}{#if h.consent_on} · {h.consent_method ?? ''} 동의 {fmtDay(h.consent_on)}{/if}
                                </span>
                            {/if}
                            {#if o?.phone}
                                <a href={`tel:${o.phone}`} class="ml-auto px-3 py-1.5 rounded-lg text-sm font-bold bg-primary-900 text-white hover:bg-primary-800">{o.phone}</a>
                            {:else}
                                <span class="ml-auto text-xs text-gray-400">번호없음</span>
                            {/if}
                        </div>
                    {/each}
                </div>
            {/if}
        {:else if view === 'add'}
            <!-- 대리 등록 — 앱 사용이 어려운 분을 대신해 등록 -->
            <div class="mb-5 rounded-2xl border border-amber-100 bg-amber-50 px-4 py-3 text-sm text-amber-900">
                <b>본인 동의를 받은 경우에만 등록하세요.</b>
                <span class="text-amber-800">
                    서면·전화 모두 가능합니다. 본인이 아닌 사람의 차량번호를 대신 등록하는 것이라,
                    누가 등록했고 동의를 언제·어떤 방법으로 받았는지가 함께 기록됩니다.
                    서면으로 받으셨다면 동의서는 교회에서 보관해 주세요.
                </span>
            </div>

            <div class="rounded-2xl border border-gray-200 bg-white p-4 sm:p-5 max-w-2xl">
                <!-- 1. 대상자 -->
                <div class="mb-4">
                    <div class="block text-xs font-bold text-gray-600 mb-1.5">1. 차주 (등록해 드릴 분)</div>
                    {#if addTarget}
                        <div class="flex items-center gap-2 rounded-xl border-2 border-primary-200 bg-primary-50 px-3 py-2.5">
                            <span class="font-bold text-gray-900">{addTarget.name}</span>
                            <span class="text-xs text-gray-500">{addTarget.office ?? ''} · {addTarget.phone || '번호없음'}</span>
                            <button type="button" onclick={() => { addTarget = null; addQuery = ''; addResults = []; }}
                                class="ml-auto px-2.5 py-1 rounded-lg text-xs font-bold border border-gray-300 text-gray-600 hover:bg-white">변경</button>
                        </div>
                    {:else}
                        <input type="text" placeholder="이름으로 검색" bind:value={addQuery} oninput={() => searchAddTargets(addQuery)}
                            class="w-full px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 text-sm" />
                        {#if addResults.length > 0}
                            <div class="mt-2 max-h-48 overflow-y-auto divide-y divide-gray-100 border border-gray-100 rounded-xl">
                                {#each addResults as r}
                                    <button type="button" onclick={() => { addTarget = r; addResults = []; }}
                                        class="w-full text-left px-3 py-2 hover:bg-primary-50 text-sm flex justify-between gap-2">
                                        <span class="font-medium">{r.name}{#if r.active === false}<span class="ml-1 text-[10px] text-gray-400 font-normal">(미가입)</span>{/if}</span>
                                        <span class="text-gray-400 text-xs">{r.office} · {r.phone || '번호없음'}</span>
                                    </button>
                                {/each}
                            </div>
                        {:else if addQuery.trim()}
                            <p class="mt-2 text-sm text-gray-400">검색 결과 없음</p>
                        {/if}
                    {/if}
                </div>

                <!-- 2. 차량 -->
                <div class="mb-4 flex flex-wrap gap-3">
                    <div>
                        <label for="ap" class="block text-xs font-bold text-gray-600 mb-1.5">2. 차량번호</label>
                        <input id="ap" type="text" bind:value={addPlate} placeholder="12가3456"
                            class="w-44 px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 text-sm font-medium" />
                    </div>
                    <div class="flex-1 min-w-[160px]">
                        <label for="am" class="block text-xs font-bold text-gray-600 mb-1.5">
                            메모 <span class="font-normal text-gray-400">(선택 · 차종·색상)</span>
                        </label>
                        <input id="am" type="text" bind:value={addMemo} placeholder="흰색 SUV"
                            class="w-full px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 text-sm" />
                    </div>
                </div>
                {#if addWarn}
                    <p class="-mt-2 mb-3 text-xs text-amber-600">번호판 형식과 달라 보입니다. 그대로 등록해도 되지만 오타가 아닌지 확인해 주세요.</p>
                {/if}

                <!-- 3. 동의 -->
                <div class="mb-4 flex flex-wrap gap-3">
                    <div>
                        <label for="acm" class="block text-xs font-bold text-gray-600 mb-1.5">3. 동의를 받은 방법</label>
                        <select id="acm" bind:value={addConsentMethod}
                            class="px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 text-sm font-medium bg-white">
                            <option value="전화">전화</option>
                            <option value="서면">서면 (동의서)</option>
                            <option value="기타">기타</option>
                        </select>
                    </div>
                    <div>
                        <label for="ac" class="block text-xs font-bold text-gray-600 mb-1.5">동의를 받은 날짜</label>
                        <input id="ac" type="date" bind:value={addConsentOn} max={todayISO()}
                            class="px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 text-sm font-medium" />
                    </div>
                </div>

                <!-- 전화로 받을 때 그냥 "등록해도 되죠?" 로 끝내면 동의로 인정받기 어렵다.
                     개인정보 보호법 제15조 제2항이 알리도록 정한 네 가지를 그대로 읽어 줄 수 있게 적어 둔다. -->
                <div class="mb-5 rounded-xl border border-gray-200 bg-gray-50 px-4 py-3">
                    <p class="text-xs font-bold text-gray-600 mb-2">동의받을 때 이렇게 안내해 주세요</p>
                    <p class="text-sm text-gray-700 leading-relaxed">
                        “교회 주차 안내를 위해 <b>차량번호와 차종·색상 메모</b>를 등록하려고 합니다.
                        이중주차 등으로 차를 빼야 할 때 차주를 확인해 연락하는 용도로만 쓰고,
                        <b>주차 담당자와 관리자만</b> 볼 수 있습니다.
                        <b>본인이 삭제하시거나 탈퇴하실 때까지</b> 보관합니다.
                        <b>동의하지 않으셔도 괜찮고</b>, 다른 서비스 이용에는 아무 제한이 없습니다. 등록해 드릴까요?”
                    </p>
                </div>

                <label class="flex items-start gap-2 mb-5 cursor-pointer">
                    <input type="checkbox" bind:checked={addConfirmed} class="mt-0.5" />
                    <span class="text-sm text-gray-700">
                        위 내용을 안내하고 본인에게 <b>동의</b>를 받았으며, 입력한 내용이 정확함을 확인합니다.
                    </span>
                </label>

                <div class="flex gap-2">
                    <button type="button" onclick={submitAdd} disabled={!canSubmitAdd}
                        class="px-5 py-2.5 rounded-xl bg-primary-900 text-white font-bold text-sm hover:bg-primary-800 disabled:opacity-40">
                        {addBusy ? '등록 중…' : '대신 등록'}
                    </button>
                    <button type="button" onclick={resetAdd}
                        class="px-4 py-2.5 rounded-xl border-2 border-gray-200 text-gray-600 font-bold text-sm hover:bg-gray-50">초기화</button>
                </div>
            </div>
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
