<script lang="ts">
    import {
        call, codesOf, today, FAITH_LABEL, FAITH_KINDS, FAITH_KIND_LABEL, STANDING_LABEL,
        type Card, type Code, type RegistryMe
    } from '$lib/registry';

    let {
        card, me, codes, personId, reload, notify
    }: {
        card: Card; me: RegistryMe; codes: Code[]; personId: string;
        reload: () => Promise<void>; notify: (text: string, isError?: boolean) => void;
    } = $props();

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

    // 신급
    let fKind = $state('baptism');
    let fDate = $state('');
    let fChurch = $state('');
    let fOfficiant = $state('');
    async function addFaith(e: SubmitEvent) {
        e.preventDefault();
        if (await run('registry_add_faith', {
            p_person_id: personId, p_kind: fKind, p_date: fDate || null,
            p_church: fChurch.trim() || null, p_officiant: fOfficiant.trim() || null
        }, '신급 기록을 추가했습니다.')) {
            fDate = ''; fChurch = ''; fOfficiant = '';
        }
    }

    // 직분
    let oCode = $state('deacon');
    let oStanding = $state('serving');
    let oDate = $state('');
    async function addOffice(e: SubmitEvent) {
        e.preventDefault();
        if (await run('registry_add_office', {
            p_person_id: personId, p_office: oCode, p_standing: oStanding, p_started_on: oDate || null
        }, '직분을 추가했습니다. 맡고 있던 직분은 그 날짜로 끝났습니다.')) {
            oDate = '';
        }
    }

    const input = 'px-3 py-2 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white text-sm';
    const label = 'block text-xs font-bold text-gray-600 mb-1';
</script>

<!-- 신급 -->
<section class="mb-10">
    <div class="flex items-baseline gap-3 mb-3">
        <h3 class="text-base font-black text-gray-900">신급</h3>
        <span class="text-sm font-bold text-primary-800">{FAITH_LABEL[card.summary.faith] ?? card.summary.faith}</span>
        {#if card.person.faith_checked_on}<span class="text-xs text-gray-400">신급 확인 {card.person.faith_checked_on}</span>{/if}
    </div>

    {#if card.faith_events.length === 0}
        <p class="text-sm text-gray-500 mb-3">
            학습·세례 기록이 없습니다.
            {#if card.summary.faith === 'unknown'}기록이 없는 것인지 원입교인인지 아직 확인하지 않아 '미확인'으로 보입니다.{/if}
        </p>
        {#if me.can_edit && !card.person.faith_checked_on}
            <button type="button" onclick={() => run('registry_save', { p_person_id: personId, p_patch: { faith_checked_on: today() } }, '원입교인으로 확인했습니다.')}
                class="mb-4 px-3 py-1.5 rounded-lg text-xs font-bold border border-gray-200 text-gray-600 hover:bg-gray-50">학습·세례를 받지 않은 원입교인으로 확인</button>
        {/if}
    {:else}
        <div class="rounded-2xl border border-gray-200 overflow-hidden mb-4">
            {#each card.faith_events as f (f.id)}
                <div class="flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-2.5 border-b border-gray-50 last:border-0 text-sm">
                    <span class="font-bold text-gray-900 w-16">{FAITH_KIND_LABEL[f.kind] ?? f.kind}</span>
                    <span class="text-gray-600">{f.event_date ?? '날짜 미상'}</span>
                    <span class="text-gray-500">{f.church_name ?? '본 교회'}</span>
                    {#if f.officiant}<span class="text-gray-400 text-xs">집례 {f.officiant}</span>{/if}
                    {#if me.can_edit}
                        <button type="button" onclick={() => run('registry_delete_faith', { p_event_id: f.id }, '기록을 지웠습니다.')}
                            class="ml-auto px-2.5 py-1 rounded-lg text-xs font-bold border border-red-200 text-red-500 hover:bg-red-50">지우기</button>
                    {/if}
                </div>
            {/each}
        </div>
    {/if}

    {#if me.can_edit}
        <form onsubmit={addFaith} class="flex flex-wrap items-end gap-2 rounded-2xl bg-gray-50 border border-gray-100 p-3">
            <div>
                <label class={label} for="fk">종류</label>
                <select id="fk" class={input} bind:value={fKind}>{#each FAITH_KINDS as k}<option value={k.kind}>{k.label}</option>{/each}</select>
            </div>
            <div><label class={label} for="fd">날짜</label><input id="fd" type="date" class={input} bind:value={fDate} /></div>
            <div><label class={label} for="fc">교회</label><input id="fc" class={input} bind:value={fChurch} placeholder="비우면 본 교회" /></div>
            <div><label class={label} for="fo">집례자</label><input id="fo" class={input} bind:value={fOfficiant} /></div>
            <button type="submit" class="px-4 py-2 rounded-xl bg-primary-900 text-white font-bold text-sm">추가</button>
        </form>
    {/if}
</section>

<!-- 직분 -->
<section>
    <h3 class="text-base font-black text-gray-900 mb-3">직분</h3>
    {#if card.office_terms.length === 0}
        <p class="text-sm text-gray-500 mb-4">직분 이력이 없습니다.</p>
    {:else}
        <div class="rounded-2xl border border-gray-200 overflow-hidden mb-4">
            {#each card.office_terms as t (t.id)}
                <div class="flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-2.5 border-b border-gray-50 last:border-0 text-sm {t.ended_on ? 'text-gray-400' : ''}">
                    <span class="font-bold {t.ended_on ? '' : 'text-gray-900'} w-20">{t.label ?? t.office}</span>
                    <span>{STANDING_LABEL[t.standing] ?? t.standing}</span>
                    <span>{t.started_on ?? '임직일 미상'} ~ {t.ended_on ?? '현재'}</span>
                    {#if t.note}<span class="text-xs text-gray-400">{t.note}</span>{/if}
                    {#if me.can_edit}
                        <span class="ml-auto flex gap-1">
                            {#if !t.ended_on}
                                <button type="button" onclick={() => run('registry_end_office', { p_term_id: t.id, p_ended_on: today() }, '직분을 오늘 날짜로 끝냈습니다.')}
                                    class="px-2.5 py-1 rounded-lg text-xs font-bold border border-gray-200 text-gray-600 hover:bg-gray-50">끝내기</button>
                            {/if}
                            <button type="button" onclick={() => run('registry_delete_office', { p_term_id: t.id }, '기록을 지웠습니다.')}
                                class="px-2.5 py-1 rounded-lg text-xs font-bold border border-red-200 text-red-500 hover:bg-red-50">지우기</button>
                        </span>
                    {/if}
                </div>
            {/each}
        </div>
    {/if}
    {#if me.can_edit}
        <form onsubmit={addOffice} class="flex flex-wrap items-end gap-2 rounded-2xl bg-gray-50 border border-gray-100 p-3">
            <div>
                <label class={label} for="oc">직분</label>
                <select id="oc" class={input} bind:value={oCode}>{#each codesOf(codes, 'office') as c}<option value={c.code}>{c.label}</option>{/each}</select>
            </div>
            <div>
                <label class={label} for="os">구분</label>
                <select id="os" class={input} bind:value={oStanding}>{#each Object.entries(STANDING_LABEL) as [k, v]}<option value={k}>{v}</option>{/each}</select>
            </div>
            <div><label class={label} for="od">임직·취임일</label><input id="od" type="date" class={input} bind:value={oDate} /></div>
            <button type="submit" class="px-4 py-2 rounded-xl bg-primary-900 text-white font-bold text-sm">추가</button>
        </form>
        <p class="text-xs text-gray-400 mt-2">직분을 추가하면 앱에 보이는 호칭도 바뀝니다(서리집사는 '집사', 은퇴는 '은퇴장로'처럼).</p>
    {/if}
</section>
