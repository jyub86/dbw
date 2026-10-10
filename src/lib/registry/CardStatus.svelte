<script lang="ts">
    import { call, today, STATUS_KINDS, STATUS_KIND_LABEL, STATUS_LABEL, type Card, type RegistryMe } from '$lib/registry';

    let {
        card, me, personId, reload, notify
    }: {
        card: Card; me: RegistryMe; personId: string;
        reload: () => Promise<void>; notify: (text: string, isError?: boolean) => void;
    } = $props();

    let kind = $state('hold');
    let date = $state(today());
    let reason = $state('');
    let church = $state('');
    const needsChurch = $derived(kind === 'transfer_in' || kind === 'transfer_out');

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

    async function add(e: SubmitEvent) {
        e.preventDefault();
        if (await run('registry_add_status', {
            p_person_id: personId, p_kind: kind, p_date: date || null,
            p_reason: reason.trim() || null, p_church: needsChurch ? church.trim() || null : null
        }, '재적 기록을 추가했습니다.')) {
            reason = ''; church = '';
        }
    }

    const input = 'px-3 py-2 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white text-sm';
    const label = 'block text-xs font-bold text-gray-600 mb-1';
</script>

<p class="text-sm text-gray-500 mb-4">
    지금 상태: <b class="text-gray-900">{STATUS_LABEL[card.summary.status] ?? card.summary.status}</b>
    <span class="text-xs text-gray-400 ml-1">(가장 최근 기록으로 정해집니다. 재적·보류는 앱에서 교인으로, 전출·별세·제적은 교인이 아닌 것으로 바뀝니다.)</span>
</p>

<div class="rounded-2xl border border-gray-200 overflow-hidden mb-4">
    {#each card.status_events as e (e.id)}
        <div class="flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-2.5 border-b border-gray-50 last:border-0 text-sm">
            <span class="font-bold text-gray-900 w-12">{STATUS_KIND_LABEL[e.kind] ?? e.kind}</span>
            <span class="text-gray-600">{e.event_date ?? '날짜 미상'}</span>
            {#if e.church_name}<span class="text-gray-500">{e.church_name}</span>{/if}
            {#if e.reason}<span class="text-gray-400 text-xs">{e.reason}</span>{/if}
            {#if me.can_edit && card.status_events.length > 1}
                <button type="button" onclick={() => run('registry_delete_status', { p_event_id: e.id }, '기록을 지웠습니다.')}
                    class="ml-auto px-2.5 py-1 rounded-lg text-xs font-bold border border-red-200 text-red-500 hover:bg-red-50">지우기</button>
            {/if}
        </div>
    {/each}
</div>

{#if me.can_edit}
    <form onsubmit={add} class="flex flex-wrap items-end gap-2 rounded-2xl bg-gray-50 border border-gray-100 p-3">
        <div>
            <label class={label} for="sk">종류</label>
            <select id="sk" class={input} bind:value={kind}>{#each STATUS_KINDS as k}<option value={k.kind}>{k.label}</option>{/each}</select>
        </div>
        <div><label class={label} for="sd">날짜</label><input id="sd" type="date" class={input} bind:value={date} required /></div>
        {#if needsChurch}
            <div><label class={label} for="sc">{kind === 'transfer_in' ? '이전 교회' : '옮겨 간 교회'}</label><input id="sc" class={input} bind:value={church} /></div>
        {/if}
        <div class="flex-1 min-w-[12rem]"><label class={label} for="sr">사유</label><input id="sr" class="{input} w-full" bind:value={reason} /></div>
        <button type="submit" class="px-4 py-2 rounded-xl bg-primary-900 text-white font-bold text-sm">추가</button>
    </form>
    <p class="text-xs text-gray-400 mt-2">교회를 떠난 교인은 교적을 지우지 말고 전출·제적으로 기록합니다. 기록은 영구 보존됩니다.</p>
{/if}
