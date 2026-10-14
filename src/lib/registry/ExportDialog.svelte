<script lang="ts">
    import { toCsv, downloadCsv, stamp, type Col } from '$lib/csv';
    import {
        EXPORT_COLUMNS, EXPORT_PURPOSES, STATUS_LABEL, FAITH_LABEL, call, codeLabel, today,
        type Code, type ExportKey
    } from '$lib/registry';

    /**
     * 교적 내려받기. 지금 목록의 조건 그대로, 용도와 항목을 고른 뒤 CSV 로 받는다.
     * DB 함수(registry_export)가 내려받기 권한·교적 비밀번호를 확인하고 용도·항목·인원을 접속기록에 남긴다.
     */
    let { filters, total, codes, onclose }: {
        filters: Record<string, unknown>;
        total: number;
        codes: Code[];
        onclose: () => void;
    } = $props();

    type Row = Partial<Record<ExportKey, unknown>>;

    const groups = [...new Set(EXPORT_COLUMNS.map((c) => c.group))];

    let purposeIdx = $state<number | null>(null);
    let detail = $state('');
    let picked = $state<ExportKey[]>(['name']);
    let busy = $state(false);
    let errorMsg = $state('');

    const preset = $derived(purposeIdx === null ? null : EXPORT_PURPOSES[purposeIdx]);
    const isOther = $derived(preset?.label === '기타');
    // 접속기록에 남는 용도: '심방 명단 — 11월 대심방' 처럼 고른 용도 + 자세한 내용
    const purpose = $derived(
        preset ? (isOther ? detail.trim() : [preset.label, detail.trim()].filter(Boolean).join(' — ')) : ''
    );
    const canSubmit = $derived(!busy && purpose.length >= 2 && picked.length > 1);

    function choose(i: number) {
        purposeIdx = i;
        picked = ['name', ...EXPORT_PURPOSES[i].columns];
    }

    function toggle(k: ExportKey) {
        if (k === 'name') return;
        picked = picked.includes(k) ? picked.filter((x) => x !== k) : [...picked, k];
    }

    function show(k: ExportKey, v: unknown): unknown {
        if (v === null || v === undefined) return '';
        if (k === 'status') return STATUS_LABEL[String(v)] ?? v;
        if (k === 'faith') return FAITH_LABEL[String(v)] ?? v;
        if (k === 'birth_lunar') return v ? '음력' : '';
        if (k === 'relation') return codeLabel(codes, 'relation', String(v));
        if (k === 'marital') return codeLabel(codes, 'marital', String(v));
        return v;
    }

    async function submit() {
        if (!canSubmit) return;
        busy = true;
        errorMsg = '';
        const r = await call<Row[]>('registry_export', { p_filters: filters, p_columns: picked, p_purpose: purpose }, '내려받지 못했습니다.');
        busy = false;
        if (!r.ok) {
            errorMsg = r.error;
            return;
        }
        // 열 순서는 항목 목록 순서를 따른다
        const cols: Col<Row>[] = EXPORT_COLUMNS.filter((c) => picked.includes(c.key)).map((c) => ({
            key: c.key,
            label: c.label,
            get: (row: Row) => show(c.key, row[c.key])
        }));
        const name = (preset?.label === '기타' ? detail.trim() : preset?.label ?? '명단').replace(/[\\/:*?"<>|\s]+/g, '_').slice(0, 30);
        downloadCsv(`교적_${name}_${stamp(today())}.csv`, toCsv(r.data ?? [], cols));
        onclose();
    }
</script>

<div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40" role="presentation" onclick={onclose}>
    <div class="bg-white rounded-3xl shadow-xl w-full max-w-2xl max-h-[90vh] overflow-y-auto p-6" role="dialog" aria-labelledby="export-title" tabindex="-1"
        onclick={(e) => e.stopPropagation()} onkeydown={(e) => e.key === 'Escape' && onclose()}>
        <h3 id="export-title" class="text-lg font-black text-gray-900 mb-1">교적 내려받기</h3>
        <p class="text-sm text-gray-500 mb-5">지금 목록 조건에 맞는 <b class="text-gray-900">{total}명</b>을 엑셀에서 여는 파일(CSV)로 받습니다.</p>

        <p class="text-xs font-bold text-gray-600 mb-2">1. 용도</p>
        <div class="flex flex-wrap gap-1.5 mb-2">
            {#each EXPORT_PURPOSES as p, i}
                <button type="button" onclick={() => choose(i)}
                    class="px-3 py-1.5 rounded-full text-sm font-bold border transition-colors
                    {purposeIdx === i ? 'bg-primary-900 border-primary-900 text-white' : 'bg-white border-gray-200 text-gray-600 hover:border-gray-400'}">
                    {p.label}
                </button>
            {/each}
        </div>
        {#if preset}
            <input type="text" bind:value={detail} maxlength="150"
                placeholder={isOther ? '용도를 적어 주세요 (필수)' : '자세한 용도 (선택, 예: 11월 대심방 · 줄기공동체)'}
                class="w-full px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 text-sm mb-5" />
        {:else}
            <p class="text-xs text-gray-400 mb-5">용도를 고르면 그 용도에 필요한 항목을 먼저 골라 둡니다.</p>
        {/if}

        <p class="text-xs font-bold text-gray-600 mb-2">2. 항목 <span class="font-normal text-gray-400">— 용도에 필요한 것만 고르세요</span></p>
        <div class="space-y-2.5 mb-5 {preset ? '' : 'opacity-40 pointer-events-none'}">
            {#each groups as g}
                <div class="flex flex-wrap items-center gap-x-4 gap-y-1.5">
                    <span class="w-14 shrink-0 text-xs font-bold text-gray-400">{g}</span>
                    {#each EXPORT_COLUMNS.filter((c) => c.group === g) as c}
                        <label class="flex items-center gap-1.5 text-sm {c.key === 'name' ? 'text-gray-400' : 'text-gray-700'}">
                            <input type="checkbox" checked={picked.includes(c.key)} disabled={c.key === 'name'} onchange={() => toggle(c.key)} />
                            {c.label}
                        </label>
                    {/each}
                </div>
            {/each}
        </div>

        <div class="rounded-2xl bg-amber-50 border border-amber-100 px-4 py-3 text-sm text-amber-900 mb-5 break-keep">
            내려받은 파일에는 교인 개인정보가 들어 있습니다. 용도가 끝나면 지워 주시고, 다른 사람에게 보내지 마세요.
            누가 언제 어떤 용도로 몇 명을 받았는지 접속기록에 남습니다. 메모는 내려받을 수 없습니다.
        </div>

        {#if errorMsg}
            <div class="mb-4 bg-red-50 border border-red-100 text-red-600 text-sm rounded-xl px-4 py-3">{errorMsg}</div>
        {/if}

        <div class="flex justify-end gap-2">
            <button type="button" onclick={onclose} class="px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-bold text-gray-600 hover:bg-gray-50">취소</button>
            <button type="button" onclick={submit} disabled={!canSubmit}
                class="px-5 py-2.5 rounded-xl bg-gray-900 text-white text-sm font-bold hover:bg-gray-700 disabled:opacity-40">
                {busy ? '만드는 중…' : `${total}명 내려받기`}
            </button>
        </div>
    </div>
</div>
