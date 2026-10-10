<script lang="ts">
    import { call, today, fmtDateTime, CONSENT_LABEL, METHOD_LABEL, type Card, type RegistryMe } from '$lib/registry';

    let {
        card, me, personId, reload, notify
    }: {
        card: Card; me: RegistryMe; personId: string;
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

    let body = $state('');
    async function addNote(e: SubmitEvent) {
        e.preventDefault();
        if (!body.trim()) return;
        if (await run('registry_add_note', { p_person_id: personId, p_body: body.trim() }, '메모를 남겼습니다.')) body = '';
    }

    let cKind = $state('registry');
    let cDate = $state(today());
    let cMethod = $state('paper');
    let cVersion = $state('');
    let cGuardian = $state('');
    async function addConsent(e: SubmitEvent) {
        e.preventDefault();
        if (await run('registry_add_consent', {
            p_person_id: personId, p_kind: cKind, p_granted_on: cDate || null, p_method: cMethod,
            p_notice_version: cVersion.trim() || null, p_guardian_name: cKind === 'guardian' ? cGuardian.trim() || null : null
        }, '동의 기록을 남겼습니다.')) {
            cVersion = ''; cGuardian = '';
        }
    }

    const input = 'px-3 py-2 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white text-sm';
    const label = 'block text-xs font-bold text-gray-600 mb-1';
</script>

<section class="mb-10">
    <h3 class="text-base font-black text-gray-900 mb-3">메모</h3>
    {#if me.can_edit}
        <form onsubmit={addNote} class="flex gap-2 mb-4">
            <textarea rows="2" bind:value={body} placeholder="담당자 메모 (교적 권한자만 봅니다)" class="{input} flex-1"></textarea>
            <button type="submit" class="px-4 py-2 rounded-xl bg-primary-900 text-white font-bold text-sm self-end">남기기</button>
        </form>
    {/if}
    {#if card.notes.length === 0}
        <p class="text-sm text-gray-400">메모가 없습니다.</p>
    {:else}
        <div class="space-y-2">
            {#each card.notes as n (n.id)}
                <div class="rounded-xl border border-gray-100 px-4 py-3">
                    <p class="text-sm text-gray-800 whitespace-pre-wrap">{n.body}</p>
                    <div class="flex items-center gap-2 mt-1.5 text-xs text-gray-400">
                        <span>{n.author ?? '알 수 없음'} · {fmtDateTime(n.created_at)}</span>
                        {#if me.can_edit}
                            <button type="button" onclick={() => run('registry_delete_note', { p_note_id: n.id }, '메모를 지웠습니다.')}
                                class="ml-auto text-red-400 hover:text-red-600">지우기</button>
                        {/if}
                    </div>
                </div>
            {/each}
        </div>
    {/if}
</section>

<section>
    <h3 class="text-base font-black text-gray-900 mb-1">동의 기록</h3>
    <p class="text-xs text-gray-400 mb-3">새가족 등록카드의 개인정보 동의, 요람 공개 동의, 14세 미만 보호자 동의를 기록합니다.</p>
    {#if card.consents.length > 0}
        <div class="rounded-2xl border border-gray-200 overflow-hidden mb-4">
            {#each card.consents as c (c.id)}
                <div class="flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-2.5 border-b border-gray-50 last:border-0 text-sm {c.revoked_on ? 'text-gray-400' : ''}">
                    <span class="font-bold {c.revoked_on ? '' : 'text-gray-900'}">{CONSENT_LABEL[c.kind] ?? c.kind}</span>
                    <span>{c.granted_on} · {METHOD_LABEL[c.method] ?? c.method}</span>
                    {#if c.notice_version}<span class="text-xs">고지문 {c.notice_version}</span>{/if}
                    {#if c.guardian_name}<span class="text-xs">보호자 {c.guardian_name}</span>{/if}
                    {#if c.revoked_on}
                        <span class="text-xs text-red-400">{c.revoked_on} 철회</span>
                    {:else if me.can_edit}
                        <button type="button" onclick={() => run('registry_revoke_consent', { p_consent_id: c.id, p_revoked_on: today() }, '철회를 기록했습니다.')}
                            class="ml-auto px-2.5 py-1 rounded-lg text-xs font-bold border border-gray-200 text-gray-600 hover:bg-gray-50">철회</button>
                    {/if}
                </div>
            {/each}
        </div>
    {:else}
        <p class="text-sm text-gray-400 mb-4">동의 기록이 없습니다.</p>
    {/if}
    {#if me.can_edit}
        <form onsubmit={addConsent} class="flex flex-wrap items-end gap-2 rounded-2xl bg-gray-50 border border-gray-100 p-3">
            <div>
                <label class={label} for="ck">종류</label>
                <select id="ck" class={input} bind:value={cKind}>{#each Object.entries(CONSENT_LABEL) as [k, v]}<option value={k}>{v}</option>{/each}</select>
            </div>
            <div><label class={label} for="cd">동의일</label><input id="cd" type="date" class={input} bind:value={cDate} /></div>
            <div>
                <label class={label} for="cm">방법</label>
                <select id="cm" class={input} bind:value={cMethod}>{#each Object.entries(METHOD_LABEL) as [k, v]}<option value={k}>{v}</option>{/each}</select>
            </div>
            <div><label class={label} for="cv">고지문 판</label><input id="cv" class={input} bind:value={cVersion} placeholder="예: 2026-10" /></div>
            {#if cKind === 'guardian'}
                <div><label class={label} for="cg">보호자</label><input id="cg" class={input} bind:value={cGuardian} /></div>
            {/if}
            <button type="submit" class="px-4 py-2 rounded-xl bg-primary-900 text-white font-bold text-sm">기록</button>
        </form>
    {/if}
</section>
