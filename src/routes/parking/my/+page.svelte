<script lang="ts">
    import { onMount } from 'svelte';
    import { goto } from '$app/navigation';
    import { supabaseBrowser } from '$lib/supabase-browser';
    import { loadParkingAccess, normalizePlate, looksLikePlate } from '$lib/parking';

    type Vehicle = { id: number; plate: string; memo: string | null; created_at: string };

    let loading = $state(true);
    let denied = $state(false);
    let saving = $state(false);
    let msg = $state('');
    let errorMsg = $state('');

    let myId = $state('');
    let canManage = $state(false);
    let vehicles = $state<Vehicle[]>([]);

    let plate = $state('');
    let memo = $state('');

    const normalized = $derived(normalizePlate(plate));
    const dup = $derived(vehicles.some((v) => normalizePlate(v.plate) === normalized));
    const warn = $derived(normalized.length >= 4 && !looksLikePlate(plate));
    const canAdd = $derived(normalized.length >= 4 && !dup && !saving);

    async function load() {
        const { data, error } = await supabaseBrowser
            .from('member_vehicles')
            .select('id, plate, memo, created_at')
            .order('created_at');
        if (error) {
            errorMsg = '차량 목록을 불러오지 못했습니다.';
            return;
        }
        vehicles = (data ?? []) as Vehicle[];
    }

    onMount(async () => {
        const { hasSession, access } = await loadParkingAccess();
        if (!hasSession) return goto('/login');
        if (!access) {
            denied = true;
            loading = false;
            return;
        }
        myId = access.userId;
        canManage = access.canManage;
        await load();
        loading = false;
    });

    async function add() {
        const p = plate.trim();
        if (!p || dup) return;
        saving = true;
        msg = '';
        errorMsg = '';
        const { error } = await supabaseBrowser
            .from('member_vehicles')
            .insert({ user_id: myId, plate: p, memo: memo.trim() || null });
        saving = false;
        if (error) {
            errorMsg = '등록 실패: ' + error.message;
            return;
        }
        plate = '';
        memo = '';
        await load();
        msg = '차량을 등록했습니다.';
    }

    async function remove(v: Vehicle) {
        if (!confirm(`${v.plate} 을(를) 삭제할까요?`)) return;
        msg = '';
        errorMsg = '';
        const { error } = await supabaseBrowser.from('member_vehicles').delete().eq('id', v.id);
        if (error) {
            errorMsg = '삭제 실패: ' + error.message;
            return;
        }
        await load();
        msg = '삭제했습니다.';
    }
</script>

<svelte:head><title>내 차량 등록 - 부평동부교회</title></svelte:head>

<div class="w-full max-w-7xl mx-auto px-6 sm:px-8 lg:px-12 py-10 sm:py-14">
    <h1 class="text-2xl sm:text-3xl font-black text-gray-900 mb-1">내 차량 등록</h1>
    <p class="text-gray-500 mb-6 text-sm sm:text-base">주차 안내를 위해 차량을 등록합니다. 여러 대 등록할 수 있습니다.</p>

    {#if canManage}
        <a href="/parking" class="inline-block mb-6 px-4 py-2 rounded-xl border-2 border-gray-200 text-gray-600 font-bold text-sm hover:bg-gray-50">주차 관리로 →</a>
    {/if}

    {#if loading}
        <div class="py-20 text-center text-gray-400">불러오는 중…</div>
    {:else if denied}
        <div class="py-20 text-center">
            <p class="text-gray-500 font-medium">프로필 정보를 찾을 수 없습니다.</p>
            <a href="/" class="inline-block mt-6 px-6 py-2.5 rounded-full bg-primary-900 text-white font-bold text-sm">홈으로</a>
        </div>
    {:else}
        <!-- 누가 볼 수 있는지 반드시 먼저 알린다 (개인정보) -->
        <div class="mb-6 rounded-2xl border border-primary-100 bg-primary-50 px-4 py-3 text-sm text-primary-900">
            <b>차량번호는 전체 공개되지 않습니다.</b>
            <span class="text-primary-800">
                본인과 주차 담당자(안내위원)·관리자만 볼 수 있으며, 이중주차 등으로 연락이 필요할 때 차주를 확인하는 용도로만 사용합니다.
                언제든 직접 삭제할 수 있습니다.
            </span>
        </div>

        {#if msg}
            <div class="mb-5 bg-green-50 border border-green-100 text-green-700 text-sm rounded-xl px-4 py-3">{msg}</div>
        {/if}
        {#if errorMsg}
            <div class="mb-5 bg-red-50 border border-red-100 text-red-600 text-sm rounded-xl px-4 py-3">{errorMsg}</div>
        {/if}

        <!-- 등록 -->
        <div class="rounded-2xl border border-gray-100 bg-gray-50 px-4 py-4 mb-6">
            <div class="flex flex-wrap items-end gap-3">
                <div>
                    <label for="plate" class="block text-xs font-bold text-gray-600 mb-1.5">차량번호</label>
                    <input id="plate" type="text" bind:value={plate} placeholder="12가3456"
                        class="px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium text-sm w-44" />
                </div>
                <div class="flex-1 min-w-[160px]">
                    <label for="memo" class="block text-xs font-bold text-gray-600 mb-1.5">
                        메모 <span class="font-normal text-gray-400">(선택 · 차종·색상)</span>
                    </label>
                    <input id="memo" type="text" bind:value={memo} placeholder="흰색 SUV"
                        class="w-full px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium text-sm" />
                </div>
                <button type="button" onclick={add} disabled={!canAdd}
                    class="px-5 py-2.5 rounded-xl bg-primary-900 text-white font-bold text-sm hover:bg-primary-800 disabled:opacity-40">
                    {saving ? '등록 중…' : '등록'}
                </button>
            </div>
            {#if dup}
                <p class="mt-2 text-xs font-bold text-red-500">이미 등록한 차량입니다.</p>
            {:else if warn}
                <p class="mt-2 text-xs text-amber-600">번호판 형식과 달라 보입니다. 그대로 등록해도 되지만 오타가 아닌지 확인해 주세요.</p>
            {/if}
        </div>

        <!-- 목록 -->
        {#if vehicles.length === 0}
            <div class="py-16 text-center text-gray-400 text-sm">등록한 차량이 없습니다.</div>
        {:else}
            <div class="rounded-2xl border border-gray-200 overflow-hidden">
                {#each vehicles as v (v.id)}
                    <div class="flex items-center gap-3 px-4 py-3 border-b border-gray-50 last:border-0">
                        <span class="font-black text-gray-900 tracking-wide">{v.plate}</span>
                        {#if v.memo}<span class="text-sm text-gray-500">{v.memo}</span>{/if}
                        <button type="button" onclick={() => remove(v)}
                            class="ml-auto px-2.5 py-1.5 rounded-lg text-xs font-bold border border-red-200 text-red-500 hover:bg-red-50">삭제</button>
                    </div>
                {/each}
            </div>
        {/if}
    {/if}
</div>
