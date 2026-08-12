<script lang="ts">
    import { onMount } from 'svelte';
    import { supabaseBrowser } from '$lib/supabase-browser';
    import {
        type ChurchEvent,
        type Occurrence,
        kstDate,
        kstTime,
        todayKST,
        addDays,
        expandEvent,
        monthGridRange,
        toKstInstant,
        weekdayOf,
        WEEKDAY_LABELS
    } from '$lib/events';

    let loading = $state(true);
    let canEdit = $state(false);
    let errorMsg = $state('');

    const today = todayKST();
    const [ty, tm] = today.split('-').map(Number);
    let year = $state(ty);
    let month = $state(tm); // 1-12
    let selectedDate = $state(today);

    let events = $state<ChurchEvent[]>([]);

    const grid = $derived(monthGridRange(year, month));
    const days = $derived(
        (() => {
            const arr: string[] = [];
            let d = grid.gridStart;
            let guard = 0;
            while (d <= grid.gridEnd && guard++ < 50) {
                arr.push(d);
                d = addDays(d, 1);
            }
            return arr;
        })()
    );

    const occByDate = $derived(
        (() => {
            const map: Record<string, Occurrence[]> = {};
            for (const ev of events) {
                for (const o of expandEvent(ev, grid.gridStart, grid.gridEnd)) {
                    (map[o.date] ??= []).push(o);
                }
            }
            for (const k of Object.keys(map)) {
                map[k].sort((a, b) => {
                    if (a.event.is_all_day !== b.event.is_all_day) return a.event.is_all_day ? -1 : 1;
                    return kstTime(a.event.start_date).localeCompare(kstTime(b.event.start_date));
                });
            }
            return map;
        })()
    );

    const selectedOccs = $derived(occByDate[selectedDate] ?? []);
    const monthLabel = $derived(`${year}년 ${month}월`);

    async function loadMonth() {
        loading = true;
        const { gridStart, gridEnd } = monthGridRange(year, month);
        const startInstant = toKstInstant(gridStart, '00:00');
        const endInstant = `${gridEnd}T23:59:59+09:00`;
        const [{ data: rec }, { data: once, error }] = await Promise.all([
            supabaseBrowser.from('church_events').select('*').neq('recurrence_type', 'none'),
            supabaseBrowser
                .from('church_events')
                .select('*')
                .eq('recurrence_type', 'none')
                .lte('start_date', endInstant)
                .gte('end_date', startInstant)
        ]);
        if (error) errorMsg = '일정을 불러오지 못했습니다.';
        events = [...((rec ?? []) as ChurchEvent[]), ...((once ?? []) as ChurchEvent[])];
        loading = false;
    }

    function goMonth(delta: number) {
        let m = month + delta;
        let y = year;
        if (m < 1) {
            m = 12;
            y -= 1;
        } else if (m > 12) {
            m = 1;
            y += 1;
        }
        year = y;
        month = m;
        // 선택일을 이 달 안으로
        selectedDate = y === ty && m === tm ? today : `${y}-${String(m).padStart(2, '0')}-01`;
        loadMonth();
    }
    function goToday() {
        year = ty;
        month = tm;
        selectedDate = today;
        loadMonth();
    }

    onMount(async () => {
        const {
            data: { session }
        } = await supabaseBrowser.auth.getSession();
        if (session) {
            const { data } = await supabaseBrowser
                .from('custom_users')
                .select('roles(level)')
                .eq('auth_id', session.user.id)
                .single();
            const level = (data?.roles as unknown as { level: number } | null)?.level ?? 0;
            canEdit = level >= 50;
        }
        await loadMonth();
    });

    function inMonth(d: string) {
        return Number(d.split('-')[1]) === month;
    }
    function dayNum(d: string) {
        return Number(d.split('-')[2]);
    }
    function eventTimeLabel(ev: ChurchEvent) {
        if (ev.is_all_day) return '종일';
        const s = kstTime(ev.start_date);
        const e = kstTime(ev.end_date);
        return e && e !== s ? `${s}–${e}` : s;
    }

    // ── 관리자 폼 ─────────────────────────────────
    let formOpen = $state(false);
    let editingId = $state<string | null>(null);
    let fTitle = $state('');
    let fDate = $state(today);
    let fAllDay = $state(false);
    let fStart = $state('10:00');
    let fEnd = $state('11:00');
    let fLocation = $state('');
    let fDesc = $state('');
    let fRecurrence = $state<'none' | 'weekly' | 'monthly' | 'yearly'>('none');
    let fRecEnd = $state('');
    let saving = $state(false);

    function openCreate() {
        editingId = null;
        fTitle = '';
        fDate = selectedDate || today;
        fAllDay = false;
        fStart = '10:00';
        fEnd = '11:00';
        fLocation = '';
        fDesc = '';
        fRecurrence = 'none';
        fRecEnd = '';
        formOpen = true;
    }
    function openEdit(ev: ChurchEvent) {
        editingId = ev.id;
        fTitle = ev.title;
        fDate = kstDate(ev.start_date);
        fAllDay = ev.is_all_day;
        fStart = kstTime(ev.start_date);
        fEnd = kstTime(ev.end_date);
        fLocation = ev.location ?? '';
        fDesc = ev.description ?? '';
        fRecurrence = (['weekly', 'monthly', 'yearly'].includes(ev.recurrence_type)
            ? ev.recurrence_type
            : 'none') as typeof fRecurrence;
        fRecEnd = ev.recurrence_end_date ? kstDate(ev.recurrence_end_date) : '';
        formOpen = true;
    }

    async function saveEvent() {
        if (!fTitle.trim()) {
            errorMsg = '제목을 입력해주세요.';
            return;
        }
        saving = true;
        errorMsg = '';
        const dom = Number(fDate.split('-')[2]);
        const moy = Number(fDate.split('-')[1]);
        const payload = {
            title: fTitle.trim(),
            description: fDesc.trim() || null,
            location: fLocation.trim() || null,
            is_all_day: fAllDay,
            start_date: fAllDay ? toKstInstant(fDate, '00:00') : toKstInstant(fDate, fStart),
            end_date: fAllDay ? toKstInstant(fDate, '23:59') : toKstInstant(fDate, fEnd),
            recurrence_type: fRecurrence,
            recurrence_end_date:
                fRecurrence !== 'none' && fRecEnd ? toKstInstant(fRecEnd, '23:59') : null,
            day_of_week: fRecurrence === 'weekly' ? weekdayOf(fDate) : null,
            day_of_month: fRecurrence === 'monthly' || fRecurrence === 'yearly' ? dom : null,
            month_of_year: fRecurrence === 'yearly' ? moy : null,
            update_at: new Date().toISOString()
        };
        const res = editingId
            ? await supabaseBrowser.from('church_events').update(payload).eq('id', editingId)
            : await supabaseBrowser.from('church_events').insert(payload);
        saving = false;
        if (res.error) {
            errorMsg = '저장에 실패했습니다. 권한을 확인해주세요.';
            return;
        }
        formOpen = false;
        await loadMonth();
    }

    async function deleteEvent(ev: ChurchEvent) {
        if (!confirm(`"${ev.title}" 일정을 삭제할까요?${ev.recurrence_type !== 'none' ? ' (반복 일정 전체가 삭제됩니다)' : ''}`))
            return;
        const { error } = await supabaseBrowser.from('church_events').delete().eq('id', ev.id);
        if (error) {
            errorMsg = '삭제에 실패했습니다.';
            return;
        }
        formOpen = false;
        await loadMonth();
    }
</script>

<svelte:head><title>교회 일정 - 부평동부교회</title></svelte:head>

<div class="w-full max-w-7xl mx-auto px-6 sm:px-8 lg:px-12 py-10 sm:py-14">
    <div class="flex items-center justify-between mb-6 flex-wrap gap-3">
        <h1 class="text-2xl sm:text-3xl font-black text-gray-900">교회 일정</h1>
        {#if canEdit}
            <button type="button" onclick={openCreate}
                class="px-5 py-2.5 rounded-full bg-primary-900 text-white font-bold text-sm hover:bg-primary-800">+ 일정 추가</button>
        {/if}
    </div>

    {#if errorMsg}
        <div class="mb-4 bg-red-50 border border-red-100 text-red-600 text-sm rounded-xl px-4 py-3">{errorMsg}</div>
    {/if}

    <!-- 월 이동 -->
    <div class="flex items-center justify-between mb-4">
        <button type="button" onclick={() => goMonth(-1)} aria-label="이전 달"
            class="w-9 h-9 rounded-full border border-gray-200 flex items-center justify-center hover:bg-gray-50">
            <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/></svg>
        </button>
        <div class="flex items-center gap-3">
            <h2 class="text-xl font-black text-gray-900">{monthLabel}</h2>
            <button type="button" onclick={goToday} class="text-xs font-bold text-primary-700 border border-primary-200 rounded-full px-3 py-1 hover:bg-primary-50">오늘</button>
        </div>
        <button type="button" onclick={() => goMonth(1)} aria-label="다음 달"
            class="w-9 h-9 rounded-full border border-gray-200 flex items-center justify-center hover:bg-gray-50">
            <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/></svg>
        </button>
    </div>

    <!-- 요일 헤더 -->
    <div class="grid grid-cols-7 text-center text-xs font-bold mb-1">
        {#each WEEKDAY_LABELS as w, i}
            <div class="py-1 {i === 0 ? 'text-red-500' : i === 6 ? 'text-blue-500' : 'text-gray-500'}">{w}</div>
        {/each}
    </div>

    <!-- 달력 그리드 -->
    {#if loading}
        <div class="py-20 text-center text-gray-400">불러오는 중…</div>
    {:else}
        <div class="grid grid-cols-7 gap-px bg-gray-100 rounded-2xl overflow-hidden border border-gray-100">
            {#each days as d}
                {@const occs = occByDate[d] ?? []}
                {@const wd = weekdayOf(d) - 1}
                <button type="button" onclick={() => (selectedDate = d)}
                    class="min-h-20 sm:min-h-24 bg-white p-1.5 text-left align-top flex flex-col gap-1 transition-colors
                    {selectedDate === d ? 'ring-2 ring-primary-400 ring-inset' : ''}
                    {!inMonth(d) ? 'bg-gray-50/60' : ''}">
                    <span class="text-xs font-bold leading-none
                        {d === today ? 'bg-primary-600 text-white rounded-full w-5 h-5 flex items-center justify-center' : ''}
                        {!inMonth(d) ? 'text-gray-300' : wd === 0 ? 'text-red-500' : wd === 6 ? 'text-blue-500' : 'text-gray-700'}">
                        {dayNum(d)}
                    </span>
                    <div class="flex flex-col gap-0.5 overflow-hidden">
                        {#each occs.slice(0, 3) as o}
                            <span class="text-[10px] leading-tight truncate px-1 py-0.5 rounded bg-primary-100 text-primary-900">{o.event.title}</span>
                        {/each}
                        {#if occs.length > 3}
                            <span class="text-[10px] text-gray-400 px-1">+{occs.length - 3}</span>
                        {/if}
                    </div>
                </button>
            {/each}
        </div>

        <!-- 선택일 상세 -->
        <section class="mt-8">
            <h3 class="text-lg font-black text-gray-900 mb-3">
                {selectedDate.split('-')[1]}월 {selectedDate.split('-')[2]}일 ({WEEKDAY_LABELS[weekdayOf(selectedDate) - 1]})
            </h3>
            {#if selectedOccs.length === 0}
                <p class="text-gray-400 text-sm">이 날의 일정이 없습니다.</p>
            {:else}
                <div class="space-y-2">
                    {#each selectedOccs as o}
                        <div class="rounded-2xl border border-gray-100 bg-white p-4">
                            <div class="flex items-start justify-between gap-3">
                                <div class="min-w-0">
                                    <div class="flex items-center gap-2 flex-wrap">
                                        <span class="font-bold text-gray-900">{o.event.title}</span>
                                        {#if o.event.recurrence_type !== 'none'}<span class="text-[10px] font-bold text-primary-700 bg-primary-50 px-1.5 py-0.5 rounded">반복</span>{/if}
                                    </div>
                                    <div class="text-sm text-gray-500 mt-1">🕑 {eventTimeLabel(o.event)}</div>
                                    {#if o.event.location}<div class="text-sm text-gray-500 mt-0.5">📍 {o.event.location}</div>{/if}
                                    {#if o.event.description}<p class="text-sm text-gray-600 mt-2 whitespace-pre-wrap">{o.event.description}</p>{/if}
                                </div>
                                {#if canEdit}
                                    <div class="flex gap-1.5 shrink-0">
                                        <button type="button" onclick={() => openEdit(o.event)} class="px-2.5 py-1.5 rounded-lg text-xs font-bold border border-gray-200 text-gray-600 hover:border-primary-400 hover:text-primary-700">수정</button>
                                        <button type="button" onclick={() => deleteEvent(o.event)} class="px-2.5 py-1.5 rounded-lg text-xs font-bold border border-red-200 text-red-500 hover:bg-red-50">삭제</button>
                                    </div>
                                {/if}
                            </div>
                        </div>
                    {/each}
                </div>
            {/if}
        </section>
    {/if}
</div>

<!-- 일정 추가/수정 모달 -->
{#if formOpen}
    <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40" role="presentation" onclick={() => (formOpen = false)}>
        <div class="bg-white rounded-3xl shadow-xl w-full max-w-md p-6 max-h-[90vh] overflow-y-auto" role="dialog" tabindex="-1" onclick={(e) => e.stopPropagation()} onkeydown={() => {}}>
            <h3 class="text-lg font-black text-gray-900 mb-4">{editingId ? '일정 수정' : '일정 추가'}</h3>
            <div class="space-y-3">
                <div>
                    <label for="ftitle" class="block text-sm font-bold text-gray-700 mb-1">제목</label>
                    <input id="ftitle" type="text" bind:value={fTitle} class="w-full px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 text-sm" />
                </div>
                <div>
                    <label for="fdate" class="block text-sm font-bold text-gray-700 mb-1">날짜</label>
                    <input id="fdate" type="date" bind:value={fDate} class="w-full px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 text-sm" />
                </div>
                <label class="flex items-center gap-2 text-sm font-medium text-gray-700">
                    <input type="checkbox" bind:checked={fAllDay} class="w-4 h-4 accent-primary-600" /> 종일
                </label>
                {#if !fAllDay}
                    <div class="grid grid-cols-2 gap-3">
                        <div>
                            <label for="fstart" class="block text-sm font-bold text-gray-700 mb-1">시작</label>
                            <input id="fstart" type="time" bind:value={fStart} class="w-full px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 text-sm" />
                        </div>
                        <div>
                            <label for="fend" class="block text-sm font-bold text-gray-700 mb-1">종료</label>
                            <input id="fend" type="time" bind:value={fEnd} class="w-full px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 text-sm" />
                        </div>
                    </div>
                {/if}
                <div>
                    <label for="floc" class="block text-sm font-bold text-gray-700 mb-1">장소 <span class="text-gray-400 font-normal">(선택)</span></label>
                    <input id="floc" type="text" bind:value={fLocation} class="w-full px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 text-sm" />
                </div>
                <div>
                    <label for="fdesc" class="block text-sm font-bold text-gray-700 mb-1">설명 <span class="text-gray-400 font-normal">(선택)</span></label>
                    <textarea id="fdesc" rows="2" bind:value={fDesc} class="w-full px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 text-sm resize-none"></textarea>
                </div>
                <div class="grid grid-cols-2 gap-3">
                    <div>
                        <label for="frec" class="block text-sm font-bold text-gray-700 mb-1">반복</label>
                        <select id="frec" bind:value={fRecurrence} class="w-full px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 text-sm bg-white">
                            <option value="none">반복 안 함</option>
                            <option value="weekly">매주</option>
                            <option value="monthly">매월</option>
                            <option value="yearly">매년</option>
                        </select>
                    </div>
                    {#if fRecurrence !== 'none'}
                        <div>
                            <label for="frecend" class="block text-sm font-bold text-gray-700 mb-1">반복 종료일</label>
                            <input id="frecend" type="date" bind:value={fRecEnd} class="w-full px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 text-sm" />
                        </div>
                    {/if}
                </div>
            </div>
            <div class="flex gap-2 mt-5">
                <button type="button" onclick={saveEvent} disabled={saving}
                    class="flex-1 py-2.5 rounded-xl bg-primary-900 text-white font-bold text-sm hover:bg-primary-800 disabled:opacity-60">
                    {saving ? '저장 중…' : editingId ? '수정' : '추가'}
                </button>
                <button type="button" onclick={() => (formOpen = false)}
                    class="px-5 py-2.5 rounded-xl border-2 border-gray-200 text-gray-600 font-bold text-sm hover:bg-gray-50">취소</button>
            </div>
        </div>
    </div>
{/if}
