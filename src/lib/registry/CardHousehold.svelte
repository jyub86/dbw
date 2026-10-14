<script lang="ts">
    import { call, codesOf, codeLabel, type Card, type Code, type PersonRow, type RegistryMe } from '$lib/registry';

    let {
        card, me, codes, personId, reload, notify
    }: {
        card: Card; me: RegistryMe; codes: Code[]; personId: string;
        reload: () => Promise<void>; notify: (text: string, isError?: boolean) => void;
    } = $props();

    const hh = $derived(card.household);
    const relations = $derived(codesOf(codes, 'relation'));

    async function run(fn: string, args: Record<string, unknown>, ok: string) {
        const r = await call(fn, args);
        if (!r.ok) {
            notify(r.error, true);
            return false;
        }
        notify(ok);
        await reload();
        return true;
    }

    // ─── 세대 주소 ───
    let editAddr = $state(false);
    let addr = $state({ address_zip: '', address1: '', address2: '', home_phone: '', note: '' });
    function startAddr() {
        if (!hh) return;
        addr = {
            address_zip: hh.address_zip ?? '', address1: hh.address1 ?? '', address2: hh.address2 ?? '',
            home_phone: hh.home_phone ?? '', note: hh.note ?? ''
        };
        editAddr = true;
    }
    async function saveAddr(e: SubmitEvent) {
        e.preventDefault();
        if (!hh) return;
        if (await run('registry_household_update', { p_household_id: hh.id, p_data: addr }, '세대 정보를 저장했습니다.')) editAddr = false;
    }

    // ─── 세대원 추가 ───
    let addOpen = $state(false);
    let addMode = $state<'member' | 'other'>('member');
    let relation = $state('spouse');
    let q = $state('');
    let found = $state<PersonRow[]>([]);
    let otherName = $state('');
    let otherBirthYear = $state('');

    async function searchPeople() {
        const t = q.trim();
        if (!t) return (found = []);
        const r = await call<PersonRow[]>('registry_search', { p_filters: { q: t }, p_limit: 20, p_offset: 0 });
        found = r.ok ? r.data.filter((x) => x.person_id !== personId) : [];
    }

    async function addMember(pid: string) {
        if (!hh) return;
        if (await run('registry_household_add', { p_household_id: hh.id, p_person_id: pid, p_relation: relation }, '세대원을 추가했습니다.')) {
            addOpen = false; q = ''; found = [];
        }
    }
    async function addOther(e: SubmitEvent) {
        e.preventDefault();
        if (!hh) return;
        const y = otherBirthYear.trim() ? Number(otherBirthYear) : null;
        if (await run('registry_household_add', {
            p_household_id: hh.id, p_person_id: null, p_relation: relation, p_name: otherName, p_birth_year: y
        }, '가족을 추가했습니다.')) {
            addOpen = false; otherName = ''; otherBirthYear = '';
        }
    }

    const input = 'w-full px-3 py-2 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white text-sm';
    const label = 'block text-xs font-bold text-gray-600 mb-1';
</script>

{#if !hh}
    <div class="py-10 text-center">
        <p class="text-gray-500 text-sm">세대 정보가 없습니다.</p>
        {#if me.can_edit}
            <button type="button" onclick={() => run('registry_household_create', { p_head: personId, p_data: {} }, '세대를 만들었습니다.')}
                class="mt-4 px-5 py-2 rounded-xl bg-primary-900 text-white font-bold text-sm hover:bg-primary-800">이 교인을 세대주로 세대 만들기</button>
            <p class="text-xs text-gray-400 mt-2">다른 세대에 넣으려면 그 세대의 세대주 카드에서 이 교인을 추가하세요.</p>
        {/if}
    </div>
{:else}
    <!-- 세대 주소 -->
    <section class="rounded-2xl border border-gray-100 p-4 mb-6">
        {#if !editAddr}
            <div class="flex items-start justify-between gap-4">
                <div class="text-sm">
                    <div class="text-xs font-bold text-gray-400">세대 주소</div>
                    <div class="text-gray-800 mt-0.5">{[hh.address_zip, hh.address1, hh.address2].filter(Boolean).join(' ') || '-'}</div>
                    <div class="text-xs font-bold text-gray-400 mt-3">집 전화</div>
                    <div class="text-gray-800 mt-0.5">{hh.home_phone || '-'}</div>
                    {#if hh.note}<p class="text-gray-500 text-xs mt-3 whitespace-pre-wrap">{hh.note}</p>{/if}
                </div>
                {#if me.can_edit}
                    <button type="button" onclick={startAddr} class="px-3 py-1.5 rounded-lg text-xs font-bold border border-gray-200 text-gray-600 hover:bg-gray-50 shrink-0">수정</button>
                {/if}
            </div>
        {:else}
            <form onsubmit={saveAddr} class="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <div><label class={label} for="h-zip">우편번호</label><input id="h-zip" class={input} bind:value={addr.address_zip} /></div>
                <div class="sm:col-span-2"><label class={label} for="h-a1">주소</label><input id="h-a1" class={input} bind:value={addr.address1} /></div>
                <div class="sm:col-span-2"><label class={label} for="h-a2">상세 주소</label><input id="h-a2" class={input} bind:value={addr.address2} /></div>
                <div><label class={label} for="h-tel">집 전화</label><input id="h-tel" class={input} bind:value={addr.home_phone} /></div>
                <div class="sm:col-span-3"><label class={label} for="h-note">메모</label><input id="h-note" class={input} bind:value={addr.note} /></div>
                <div class="sm:col-span-3 flex gap-2">
                    <button type="submit" class="px-4 py-2 rounded-xl bg-primary-900 text-white font-bold text-sm">저장</button>
                    <button type="button" onclick={() => (editAddr = false)} class="px-4 py-2 rounded-xl border border-gray-200 text-gray-600 font-bold text-sm">취소</button>
                </div>
            </form>
        {/if}
    </section>

    <!-- 세대원 -->
    <div class="rounded-2xl border border-gray-200 overflow-hidden mb-4">
        {#each hh.members as m (m.id)}
            <div class="flex flex-wrap items-center gap-x-3 gap-y-1 px-4 py-3 border-b border-gray-50 last:border-0">
                {#if me.can_edit}
                    <select value={m.relation} class="px-2 py-1 rounded-lg border border-gray-200 text-xs bg-white"
                        onchange={(e) => run('registry_household_member_update', { p_member_id: m.id, p_relation: (e.currentTarget as HTMLSelectElement).value }, '관계를 바꿨습니다.')}>
                        {#each relations as c}<option value={c.code}>{c.label}</option>{/each}
                    </select>
                {:else}
                    <span class="text-xs font-bold text-gray-500 w-14">{codeLabel(codes, 'relation', m.relation)}</span>
                {/if}
                {#if m.person_id}
                    <a href={`/registry/${m.person_id}`} class="font-bold text-gray-900 hover:text-primary-700 {m.person_id === personId ? 'underline' : ''}">{m.name}</a>
                    <span class="text-xs text-gray-400">{m.office ?? ''}</span>
                {:else}
                    <span class="font-bold text-gray-700">{m.name}</span>
                    <span class="text-xs text-gray-400">교인 아님</span>
                {/if}
                {#if m.birth_year}<span class="text-xs text-gray-400">{m.birth_year}년생</span>{/if}
                {#if me.can_edit}
                    <button type="button" onclick={() => run('registry_household_remove', { p_member_id: m.id }, '세대에서 뺐습니다.')}
                        class="ml-auto px-2.5 py-1 rounded-lg text-xs font-bold border border-red-200 text-red-500 hover:bg-red-50">빼기</button>
                {/if}
            </div>
        {/each}
    </div>
    <p class="text-xs text-gray-400 mb-6">관계는 세대주(본인) 기준입니다. 세대주를 바꾸려면 지금 세대주의 관계를 먼저 바꾼 뒤 새 세대주를 '본인'으로 고르세요.</p>

    {#if me.can_edit}
        {#if !addOpen}
            <button type="button" onclick={() => (addOpen = true)} class="px-4 py-2 rounded-xl bg-gray-900 text-white font-bold text-sm hover:bg-gray-700">+ 세대원 추가</button>
        {:else}
            <section class="rounded-2xl border border-gray-200 bg-gray-50 p-4 space-y-3">
                <div class="flex flex-wrap items-end gap-3">
                    <div>
                        <label class={label} for="h-rel">관계</label>
                        <select id="h-rel" bind:value={relation} class="px-3 py-2 rounded-xl border-2 border-gray-200 bg-white text-sm">
                            {#each relations as c}<option value={c.code}>{c.label}</option>{/each}
                        </select>
                    </div>
                    <div class="flex gap-1 bg-white rounded-xl p-1 border border-gray-200">
                        <button type="button" onclick={() => (addMode = 'member')} class="px-3 py-1.5 rounded-lg text-xs font-bold {addMode === 'member' ? 'bg-gray-900 text-white' : 'text-gray-500'}">교인</button>
                        <button type="button" onclick={() => (addMode = 'other')} class="px-3 py-1.5 rounded-lg text-xs font-bold {addMode === 'other' ? 'bg-gray-900 text-white' : 'text-gray-500'}">교인 아닌 가족</button>
                    </div>
                    <button type="button" onclick={() => (addOpen = false)} class="ml-auto text-xs text-gray-500 underline">닫기</button>
                </div>
                {#if addMode === 'member'}
                    <div class="flex gap-2">
                        <input class={input} bind:value={q} placeholder="교적에서 이름으로 찾기" onkeydown={(e) => e.key === 'Enter' && (e.preventDefault(), searchPeople())} />
                        <button type="button" onclick={searchPeople} class="px-4 py-2 rounded-xl bg-gray-900 text-white font-bold text-sm shrink-0">찾기</button>
                    </div>
                    <div class="divide-y divide-gray-100 bg-white rounded-xl">
                        {#each found as r}
                            <div class="flex items-center justify-between px-3 py-2 text-sm">
                                <span><b>{r.name}</b> <span class="text-xs text-gray-400">{r.office ?? ''} · {r.group_name ?? '소그룹 없음'} · {r.birth_date ?? ''}</span></span>
                                <button type="button" onclick={() => addMember(r.person_id)} class="px-3 py-1.5 rounded-lg text-xs font-bold bg-primary-900 text-white">추가</button>
                            </div>
                        {/each}
                    </div>
                    <p class="text-xs text-gray-400">다른 세대에 있던 교인이면 이 세대로 옮겨집니다.</p>
                {:else}
                    <form onsubmit={addOther} class="flex flex-wrap gap-2 items-end">
                        <div class="flex-1 min-w-[10rem]"><label class={label} for="h-oname">이름</label><input id="h-oname" class={input} bind:value={otherName} required /></div>
                        <div class="w-32"><label class={label} for="h-oyear">출생연도</label><input id="h-oyear" class={input} bind:value={otherBirthYear} inputmode="numeric" placeholder="예: 2015" /></div>
                        <button type="submit" class="px-4 py-2 rounded-xl bg-primary-900 text-white font-bold text-sm">추가</button>
                    </form>
                {/if}
            </section>
        {/if}
    {/if}
{/if}
