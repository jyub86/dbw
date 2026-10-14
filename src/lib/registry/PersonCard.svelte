<script lang="ts">
    import { onMount } from 'svelte';
    import { goto } from '$app/navigation';
    import {
        STATUS_LABEL, STATUS_STYLE, FAITH_LABEL, STANDING_LABEL, call, loadCodes, codesOf, codeLabel, age,
        type Card, type Code, type RegistryMe
    } from '$lib/registry';
    import CardHousehold from './CardHousehold.svelte';
    import CardFaith from './CardFaith.svelte';
    import CardStatus from './CardStatus.svelte';
    import CardNotes from './CardNotes.svelte';
    import CardHistory from './CardHistory.svelte';

    let { me, personId }: { me: RegistryMe; personId: string } = $props();

    type Tab = 'basic' | 'household' | 'faith' | 'status' | 'notes' | 'history';
    const TABS: { key: Tab; name: string }[] = [
        { key: 'basic', name: '기본 정보' },
        { key: 'household', name: '세대' },
        { key: 'faith', name: '신급·직분' },
        { key: 'status', name: '재적 이력' },
        { key: 'notes', name: '메모·동의' },
        { key: 'history', name: '변경 이력' }
    ];

    let card = $state<Card | null>(null);
    let codes = $state<Code[]>([]);
    let tab = $state<Tab>('basic');
    let loading = $state(true);
    let loadError = $state('');
    let msg = $state('');
    let errorMsg = $state('');

    function notify(text: string, isError = false) {
        msg = isError ? '' : text;
        errorMsg = isError ? text : '';
    }

    async function reload() {
        const r = await call<Card>('registry_card', { p_person_id: personId }, '교적을 불러오지 못했습니다.');
        loading = false;
        if (!r.ok) {
            loadError = r.error;
            return;
        }
        card = r.data;
    }

    // ─── 기본 정보 수정 ───
    const PROFILE_KEYS = ['name', 'phone', 'gender', 'birth_date'] as const;
    const REG_KEYS = ['name_note', 'birth_lunar', 'address_zip', 'address1', 'address2', 'occupation', 'workplace',
        'marital_status', 'wedding_date', 'previous_church', 'guide_name', 'sms_opt_out', 'note'] as const;
    // 입력칸은 문자열, 체크칸(birth_lunar·sms_opt_out)은 boolean
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    type Form = Record<string, any>;

    let editing = $state(false);
    let form = $state<Form>({});
    let saving = $state(false);

    function startEdit() {
        if (!card) return;
        const p = card.person as unknown as Record<string, unknown>;
        const f: Form = {};
        for (const k of [...PROFILE_KEYS, ...REG_KEYS]) {
            const v = p[k];
            f[k] = typeof v === 'boolean' ? v : ((v as string | null) ?? '');
        }
        form = f;
        editing = true;
    }

    async function save(e: SubmitEvent) {
        e.preventDefault();
        if (!card || saving) return;
        // 바뀐 칸만 보낸다. 빈 칸은 비움(null)으로
        const p = card.person as unknown as Record<string, unknown>;
        const patch: Record<string, unknown> = {};
        for (const k of [...PROFILE_KEYS, ...REG_KEYS]) {
            const v = typeof form[k] === 'string' ? (form[k] as string).trim() : form[k];
            const before = p[k] ?? (typeof v === 'boolean' ? false : '');
            if (v !== before) patch[k] = v === '' ? null : v;
        }
        if (Object.keys(patch).length === 0) {
            editing = false;
            return;
        }
        saving = true;
        const r = await call('registry_save', { p_person_id: personId, p_patch: patch }, '저장하지 못했습니다.');
        saving = false;
        if (!r.ok) return notify(r.error, true);
        editing = false;
        notify('저장했습니다.');
        await reload();
    }

    // ─── 계정 연결 (미가입 교인 ↔ 가입한 계정) ───
    type Similar = { person_id: string; name: string | null; office: string | null; phone: string | null; has_account: boolean; in_registry: boolean; group_name: string | null };
    let linkOpen = $state(false);
    let linkQuery = $state('');
    let linkResults = $state<Similar[]>([]);

    async function searchAccounts() {
        const t = linkQuery.trim();
        if (!t) return (linkResults = []);
        const r = await call<Similar[]>('registry_find_similar', { p_name: t, p_phone: t.replace(/\D/g, '') || null });
        linkResults = r.ok ? r.data.filter((x) => x.has_account && x.person_id !== personId) : [];
    }

    async function link(accountId: string) {
        const r = await call('registry_link_account', { p_person_id: personId, p_account_id: accountId }, '연결하지 못했습니다.');
        if (!r.ok) return notify(r.error, true);
        // 교적이 가입 계정 쪽으로 옮겨졌다 → 그 카드로
        goto(`/registry/${accountId}`, { replaceState: true });
    }

    // ─── 잘못 만든 교적 지우기 ───
    let dangerOpen = $state(false);
    let unenrollReason = $state('');

    async function unenroll() {
        const r = await call('registry_unenroll', { p_person_id: personId, p_reason: unenrollReason }, '지우지 못했습니다.');
        if (!r.ok) return notify(r.error, true);
        goto('/registry', { replaceState: true });
    }

    onMount(async () => {
        codes = await loadCodes();
        await reload();
    });

    const input = 'w-full px-3 py-2 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white text-sm';
    const label = 'block text-xs font-bold text-gray-600 mb-1';
</script>

{#if loading}
    <div class="py-20 text-center text-gray-400">불러오는 중…</div>
{:else if loadError || !card}
    <div class="py-20 text-center">
        <p class="text-gray-500 font-medium">{loadError || '교적을 찾지 못했습니다.'}</p>
        <a href="/registry" class="inline-block mt-6 px-6 py-2.5 rounded-full bg-primary-900 text-white font-bold text-sm">교인 목록으로</a>
    </div>
{:else}
    {@const p = card.person}
    {@const s = card.summary}
    {@const a = age(p.birth_date)}
    <!-- 머리말 -->
    <div class="flex flex-wrap items-start gap-4 mb-6">
        {#if p.photo}
            <img src={p.photo} alt="" class="w-16 h-16 rounded-2xl object-cover bg-gray-100" />
        {/if}
        <div class="flex-1 min-w-0">
            <div class="flex flex-wrap items-center gap-2">
                <h2 class="text-2xl font-black text-gray-900">{p.name ?? '(이름없음)'}</h2>
                {#if p.name_note}<span class="text-sm text-gray-400">{p.name_note}</span>{/if}
                <span class="text-gray-500 font-bold">{p.office ?? ''}</span>
                <span class="px-2 py-0.5 rounded-full text-xs font-bold {STATUS_STYLE[s.status] ?? ''}">{STATUS_LABEL[s.status] ?? s.status}</span>
                <span class="px-2 py-0.5 rounded-full text-xs font-bold bg-gray-100 text-gray-600">{FAITH_LABEL[s.faith] ?? s.faith}</span>
                {#if p.has_account}<span class="px-2 py-0.5 rounded-full text-xs font-bold bg-blue-50 text-blue-600">앱 가입</span>{/if}
            </div>
            <p class="text-sm text-gray-500 mt-1">
                {p.gender ?? '성별 미상'}{a !== null ? ` · ${a}세` : ''}
                {s.community_name ? ` · ${s.community_name} ${s.group_name}` : ' · 소그룹 없음'}
                {p.reg_no ? ` · 교번 ${p.reg_no}` : ''}
            </p>
        </div>
        <a href="/registry" class="px-3 py-1.5 rounded-lg text-xs font-bold border border-gray-200 text-gray-600 hover:bg-gray-50">목록</a>
    </div>

    {#if p.purged_on}
        <div class="mb-5 rounded-2xl bg-gray-50 border border-gray-200 px-4 py-3 text-sm text-gray-600 break-keep">
            {p.purged_on}에 인적사항을 파기했습니다(전출·별세·제적 후 5년, 개인정보처리방침). 이름·재적·신급·직분 기록만 남아 있습니다.
        </div>
    {/if}

    <div class="flex flex-wrap gap-1 mb-5 border-b border-gray-100">
        {#each TABS as t}
            <button type="button" onclick={() => { tab = t.key; notify(''); }}
                class="px-3 py-2 text-sm font-bold border-b-2 -mb-px transition-colors {tab === t.key ? 'border-primary-700 text-primary-800' : 'border-transparent text-gray-500 hover:text-gray-800'}">
                {t.name}
            </button>
        {/each}
    </div>

    {#if msg}
        <div class="mb-5 bg-primary-50 border border-primary-100 text-primary-800 text-sm rounded-xl px-4 py-3">{msg}</div>
    {/if}
    {#if errorMsg}
        <div class="mb-5 bg-red-50 border border-red-100 text-red-600 text-sm rounded-xl px-4 py-3">{errorMsg}</div>
    {/if}

    {#if tab === 'basic'}
        {#if !editing}
            <dl class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-x-6 gap-y-4 mb-6">
                {#each [
                    ['전화', p.phone],
                    ['생년월일', p.birth_date ? `${p.birth_date}${p.birth_lunar ? ' (음력)' : ''}` : null],
                    ['이메일 (앱 계정)', p.email],
                    ['주소', [p.address_zip, p.address1, p.address2].filter(Boolean).join(' ') || (card.household?.address1 ? `${card.household.address1} ${card.household.address2 ?? ''} (세대 주소)` : null)],
                    ['직업', p.occupation],
                    ['직장·학교', p.workplace],
                    ['결혼', codeLabel(codes, 'marital', p.marital_status) || null],
                    ['결혼기념일', p.wedding_date],
                    ['이전 교회', p.previous_church],
                    ['인도자', card.guide ?? p.guide_name],
                    ['등록일', s.registered_on ?? '미상'],
                    ['직분', s.office ? `${codeLabel(codes, 'office', s.office)} (${STANDING_LABEL[s.standing ?? ''] ?? ''})` : '없음'],
                    ['문자 수신', p.sms_opt_out ? '거부' : '받음']
                ] as [k, v]}
                    <div>
                        <dt class="text-xs font-bold text-gray-400">{k}</dt>
                        <dd class="text-sm text-gray-800 mt-0.5 break-words">{v || '-'}</dd>
                    </div>
                {/each}
            </dl>
            {#if p.note}
                <div class="mb-6">
                    <div class="text-xs font-bold text-gray-400">비고</div>
                    <p class="text-sm text-gray-800 mt-0.5 whitespace-pre-wrap">{p.note}</p>
                </div>
            {/if}
            {#if card.groups.length}
                <div class="mb-6">
                    <div class="text-xs font-bold text-gray-400 mb-1">소그룹 소속 (출석부)</div>
                    <div class="flex flex-wrap gap-1.5">
                        {#each card.groups as g}
                            <span class="px-2.5 py-1 rounded-lg text-xs {g.active ? 'bg-gray-100 text-gray-700' : 'bg-gray-50 text-gray-400 line-through'}">
                                {g.community_name} · {g.group_name}{g.role === 'leader' ? ' (리더)' : ''}
                            </span>
                        {/each}
                    </div>
                    <p class="text-xs text-gray-400 mt-1">소그룹 이동은 출석부의 명단 관리에서 합니다.</p>
                </div>
            {/if}
            {#if me.can_edit}
                <button type="button" onclick={startEdit} class="px-4 py-2 rounded-xl bg-primary-900 text-white font-bold text-sm hover:bg-primary-800">수정</button>
            {/if}
        {:else}
            <form onsubmit={save} class="space-y-4">
                <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                    <div><label class={label} for="f-name">이름</label><input id="f-name" class={input} bind:value={form.name} required /></div>
                    <div><label class={label} for="f-note">동명이인 구분</label><input id="f-note" class={input} bind:value={form.name_note} placeholder="예: 1965년생" /></div>
                    <div><label class={label} for="f-phone">전화</label><input id="f-phone" class={input} bind:value={form.phone} inputmode="tel" /></div>
                    <div>
                        <label class={label} for="f-gender">성별</label>
                        <select id="f-gender" class={input} bind:value={form.gender}>
                            <option value="">미상</option><option value="남">남</option><option value="여">여</option>
                        </select>
                    </div>
                    <div>
                        <label class={label} for="f-birth">생년월일</label>
                        <input id="f-birth" type="date" class={input} bind:value={form.birth_date} />
                        <label class="inline-flex items-center gap-1.5 mt-1.5 text-xs text-gray-600"><input type="checkbox" bind:checked={form.birth_lunar} /> 음력</label>
                    </div>
                    <div>
                        <label class={label} for="f-marital">결혼</label>
                        <select id="f-marital" class={input} bind:value={form.marital_status}>
                            <option value="">미상</option>
                            {#each codesOf(codes, 'marital') as c}<option value={c.code}>{c.label}</option>{/each}
                        </select>
                    </div>
                    <div><label class={label} for="f-zip">우편번호</label><input id="f-zip" class={input} bind:value={form.address_zip} /></div>
                    <div class="sm:col-span-2"><label class={label} for="f-addr1">주소</label><input id="f-addr1" class={input} bind:value={form.address1} placeholder="비워 두면 세대 주소를 씁니다" /></div>
                    <div class="sm:col-span-2 lg:col-span-3"><label class={label} for="f-addr2">상세 주소</label><input id="f-addr2" class={input} bind:value={form.address2} /></div>
                    <div><label class={label} for="f-job">직업</label><input id="f-job" class={input} bind:value={form.occupation} /></div>
                    <div><label class={label} for="f-work">직장·학교</label><input id="f-work" class={input} bind:value={form.workplace} /></div>
                    <div><label class={label} for="f-wed">결혼기념일</label><input id="f-wed" type="date" class={input} bind:value={form.wedding_date} /></div>
                    <div><label class={label} for="f-prev">이전 교회</label><input id="f-prev" class={input} bind:value={form.previous_church} /></div>
                    <div><label class={label} for="f-guide">인도자</label><input id="f-guide" class={input} bind:value={form.guide_name} /></div>
                    <div class="flex items-end pb-2">
                        <label class="inline-flex items-center gap-1.5 text-sm text-gray-700"><input type="checkbox" bind:checked={form.sms_opt_out} /> 문자 수신 거부</label>
                    </div>
                    <div class="sm:col-span-2 lg:col-span-3"><label class={label} for="f-memo">비고</label><textarea id="f-memo" rows="3" class={input} bind:value={form.note}></textarea></div>
                </div>
                <div class="flex gap-2">
                    <button type="submit" disabled={saving} class="px-5 py-2 rounded-xl bg-primary-900 text-white font-bold text-sm hover:bg-primary-800 disabled:opacity-50">저장</button>
                    <button type="button" onclick={() => (editing = false)} class="px-5 py-2 rounded-xl border border-gray-200 text-gray-600 font-bold text-sm hover:bg-gray-50">취소</button>
                </div>
                <p class="text-xs text-gray-400">이름·전화·성별·생년월일은 앱 프로필과 같은 값입니다. 여기서 고치면 앱에도 반영됩니다.</p>
            </form>
        {/if}

        {#if me.can_edit && !p.has_account && !editing}
            <section class="mt-10 rounded-2xl border border-gray-100 p-4">
                <div class="flex items-center justify-between">
                    <div>
                        <h3 class="font-black text-gray-900 text-sm">가입한 계정과 연결</h3>
                        <p class="text-xs text-gray-500 mt-0.5">이 교인이 앱에 가입했는데 이름·전화가 달라 자동으로 합쳐지지 않았을 때 씁니다.</p>
                    </div>
                    <button type="button" onclick={() => { linkOpen = !linkOpen; linkQuery = p.name ?? ''; linkResults = []; }}
                        class="px-3 py-1.5 rounded-lg text-xs font-bold border border-gray-200 text-gray-600 hover:bg-gray-50">{linkOpen ? '닫기' : '연결'}</button>
                </div>
                {#if linkOpen}
                    <div class="mt-3 flex gap-2">
                        <input class={input} bind:value={linkQuery} placeholder="가입자 이름 또는 전화번호" />
                        <button type="button" onclick={searchAccounts} class="px-4 py-2 rounded-xl bg-gray-900 text-white font-bold text-sm shrink-0">찾기</button>
                    </div>
                    <div class="mt-2 divide-y divide-gray-50">
                        {#each linkResults as r}
                            <div class="flex items-center justify-between py-2 text-sm">
                                <span><b>{r.name}</b> <span class="text-gray-400 text-xs">{r.office ?? ''} · {r.phone ?? '번호없음'}{r.in_registry ? ' · 교적 있음' : ''}</span></span>
                                <button type="button" onclick={() => link(r.person_id)} class="px-3 py-1.5 rounded-lg text-xs font-bold bg-primary-900 text-white">이 계정과 연결</button>
                            </div>
                        {/each}
                    </div>
                    <p class="text-xs text-gray-400 mt-2">연결하면 이 교인의 교적·소그룹·출석 기록이 가입한 계정으로 옮겨지고, 이 미가입 프로필은 없어집니다.</p>
                {/if}
            </section>
        {/if}

        {#if me.can_edit && !editing}
            <section class="mt-6">
                <button type="button" onclick={() => (dangerOpen = !dangerOpen)} class="text-xs text-gray-400 underline">잘못 만든 교적 지우기</button>
                {#if dangerOpen}
                    <div class="mt-2 rounded-2xl border border-red-100 bg-red-50/40 p-4">
                        <p class="text-xs text-red-700 mb-2">중복 등 <b>잘못 만든 교적</b>만 지웁니다. 교회를 떠난 교인은 지우지 말고 재적 이력에서 전출·제적으로 처리하세요. 지운 내용은 변경기록에 남습니다.</p>
                        <div class="flex gap-2">
                            <input class={input} bind:value={unenrollReason} placeholder="지우는 이유 (필수)" />
                            <button type="button" onclick={unenroll} disabled={!unenrollReason.trim()}
                                class="px-4 py-2 rounded-xl border border-red-200 text-red-600 font-bold text-sm bg-white hover:bg-red-50 disabled:opacity-40 shrink-0">지우기</button>
                        </div>
                    </div>
                {/if}
            </section>
        {/if}
    {:else if tab === 'household'}
        <CardHousehold {card} {me} {codes} {personId} {reload} {notify} />
    {:else if tab === 'faith'}
        <CardFaith {card} {me} {codes} {personId} {reload} {notify} />
    {:else if tab === 'status'}
        <CardStatus {card} {me} {personId} {reload} {notify} />
    {:else if tab === 'notes'}
        <CardNotes {card} {me} {personId} {reload} {notify} />
    {:else}
        <CardHistory {card} />
    {/if}
{/if}
