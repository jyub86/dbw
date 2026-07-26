<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { supabaseBrowser } from '$lib/supabase-browser';
	import { loadEducationAccess, DEPARTMENTS, sundayList, fmtFullDate, thisSunday } from '$lib/education';
	import EducationNav from '$lib/components/EducationNav.svelte';

	type PlanFields = { this_week: string; next_week: string; event_note: string };

	let loading = $state(true);
	let denied = $state(false);
	let saving = $state(false);
	let msg = $state('');
	let dept = $state<string>(DEPARTMENTS[0]);

	const thisWk = thisSunday();
	const DEFAULT_DATES = sundayList(0, 12).reverse(); // 이번 주 → 앞으로 12주 (오름차순)
	const ALL_SUNDAYS = sundayList(12, 78); // 추가 선택용 넓은 범위 (과거 12주 ~ 앞으로 78주)

	let dates = $state<string[]>([]); // 화면에 표시 중인 주 (오름차순)
	let plan = $state<Record<string, PlanFields>>({});
	let existed = $state<Set<string>>(new Set());
	let addPick = $state<string>('');

	// 아직 표시되지 않은, 추가 가능한 일요일 (오름차순)
	const addable = $derived(
		ALL_SUNDAYS.filter((s) => !dates.includes(s)).sort((a, b) => (a < b ? -1 : 1))
	);

	onMount(async () => {
		const { hasSession, access } = await loadEducationAccess();
		if (!hasSession) {
			goto('/login');
			return;
		}
		if (!access || !access.canAccess) {
			denied = true;
			loading = false;
			return;
		}
		dates = [...DEFAULT_DATES];
		await loadPlan();
		loading = false;
	});

	// 현재 dept + 현재 dates 전체를 DB에서 다시 로드 (마운트·부서변경 시).
	async function loadPlan() {
		msg = '';
		const { data } = await supabaseBrowser
			.from('education_reports')
			.select('report_date, this_week, next_week, event_note')
			.eq('department', dept)
			.in('report_date', dates);
		const found = new Set<string>();
		const next: Record<string, PlanFields> = {};
		for (const d of dates) next[d] = { this_week: '', next_week: '', event_note: '' };
		for (const r of (data ?? []) as {
			report_date: string;
			this_week: string | null;
			next_week: string | null;
			event_note: string | null;
		}[]) {
			found.add(r.report_date);
			next[r.report_date] = {
				this_week: r.this_week ?? '',
				next_week: r.next_week ?? '',
				event_note: r.event_note ?? ''
			};
		}
		plan = next;
		existed = found;
	}

	async function changeDept(d: string) {
		dept = d;
		loading = true;
		await loadPlan(); // 현재 표시 중인 주 유지
		loading = false;
	}

	// 다른 주 추가: 해당 주만 DB 조회 후 목록에 끼워넣음 (다른 행의 미저장 입력은 유지)
	async function addWeek() {
		const d = addPick;
		if (!d || dates.includes(d)) return;
		const { data } = await supabaseBrowser
			.from('education_reports')
			.select('this_week, next_week, event_note')
			.eq('department', dept)
			.eq('report_date', d)
			.maybeSingle();
		plan[d] = data
			? {
					this_week: data.this_week ?? '',
					next_week: data.next_week ?? '',
					event_note: data.event_note ?? ''
				}
			: { this_week: '', next_week: '', event_note: '' };
		if (data) existed = new Set(existed).add(d);
		dates = [...dates, d].sort((a, b) => (a < b ? -1 : 1));
		addPick = '';
	}

	async function save() {
		saving = true;
		msg = '';
		// 내용이 있거나 이미 존재하던 행만 대상 (빈 미래 행 양산 방지, 기존 행은 비우기 허용)
		const payload = dates
			.filter((d) => {
				const f = plan[d];
				const has = f.this_week.trim() || f.next_week.trim() || f.event_note.trim();
				return has || existed.has(d);
			})
			.map((d) => ({
				report_date: d,
				department: dept,
				this_week: plan[d].this_week.trim() || null,
				next_week: plan[d].next_week.trim() || null,
				event_note: plan[d].event_note.trim() || null
			}));

		if (payload.length === 0) {
			saving = false;
			msg = '입력된 내용이 없습니다.';
			return;
		}
		// 교육·행사 컬럼만 upsert → 출석현황(재적/출석 등)은 보존됨
		const { error } = await supabaseBrowser
			.from('education_reports')
			.upsert(payload, { onConflict: 'report_date,department' });
		saving = false;
		if (error) {
			msg = '저장 실패: ' + error.message;
			return;
		}
		await loadPlan();
		msg = `${dept} 계획이 저장되었습니다.`;
	}
</script>

<svelte:head><title>교육부서 계획 - 부평동부교회</title></svelte:head>

<div class="w-full max-w-3xl mx-auto px-5 sm:px-8 py-10 sm:py-14">
	<h1 class="text-2xl sm:text-3xl font-black text-gray-900 mb-1">교육·행사 미리 계획</h1>
	<p class="text-gray-500 mb-6 text-sm sm:text-base">앞으로의 교육·행사 계획을 주별로 미리 입력합니다. (출석 숫자는 각 주 보고서에서 입력)</p>

	<EducationNav />

	{#if loading}
		<div class="py-20 text-center text-gray-400">불러오는 중…</div>
	{:else if denied}
		<div class="py-20 text-center">
			<p class="text-gray-500 font-medium">접근 권한이 없습니다.</p>
			<a href="/" class="inline-block mt-6 px-6 py-2.5 rounded-full bg-primary-900 text-white font-bold text-sm">홈으로</a>
		</div>
	{:else}
		<!-- 부서 선택 -->
		<div class="flex flex-wrap gap-1.5 mb-4">
			{#each DEPARTMENTS as d}
				<button type="button" onclick={() => changeDept(d)}
					class="px-3.5 py-2 rounded-xl text-sm font-bold border-2 transition-colors {dept === d ? 'bg-primary-900 text-white border-primary-900' : 'border-gray-200 text-gray-600 hover:border-primary-400'}">
					{d}
				</button>
			{/each}
		</div>

		<!-- 다른 주 추가 -->
		<div class="mb-5 flex items-end gap-2 flex-wrap rounded-2xl border border-gray-100 bg-gray-50 px-4 py-3">
			<div>
				<label for="addwk" class="block text-[11px] font-bold text-gray-600 mb-1">다른 주 추가</label>
				<select id="addwk" bind:value={addPick}
					class="px-3 py-2 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium text-sm">
					<option value="">주일 선택…</option>
					{#each addable as s}
						<option value={s}>{fmtFullDate(s)}</option>
					{/each}
				</select>
			</div>
			<button type="button" onclick={addWeek} disabled={!addPick}
				class="px-4 py-2 rounded-xl bg-gray-900 text-white font-bold text-sm hover:bg-gray-700 disabled:opacity-40">+ 추가</button>
		</div>

		{#if msg}
			<div class="mb-5 bg-primary-50 border border-primary-100 text-primary-800 text-sm rounded-xl px-4 py-3">{msg}</div>
		{/if}

		<div class="space-y-4">
			{#each dates as d}
				<div class="rounded-2xl border border-gray-200 p-4">
					<div class="flex items-center gap-2 mb-3">
						<h3 class="font-black text-gray-900 text-sm">{fmtFullDate(d)}</h3>
						{#if d === thisWk}<span class="text-[10px] font-bold text-primary-700 bg-primary-50 px-1.5 py-0.5 rounded">이번 주</span>{/if}
						{#if existed.has(d)}<span class="text-[10px] font-bold text-gray-400 bg-gray-100 px-1.5 py-0.5 rounded">작성됨</span>{/if}
					</div>
					<div class="mb-2.5">
						<label for={`${d}-tw`} class="block text-[11px] font-bold text-gray-500 mb-1">이번 주 (교육·활동)</label>
						<textarea id={`${d}-tw`} rows="2" bind:value={plan[d].this_week}
							class="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm focus:outline-none focus:border-primary-500 resize-y"></textarea>
					</div>
					<div class="grid sm:grid-cols-2 gap-2.5">
						<div>
							<label for={`${d}-nw`} class="block text-[11px] font-bold text-gray-500 mb-1">다음 주</label>
							<textarea id={`${d}-nw`} rows="2" bind:value={plan[d].next_week}
								class="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm focus:outline-none focus:border-primary-500 resize-y"></textarea>
						</div>
						<div>
							<label for={`${d}-en`} class="block text-[11px] font-bold text-gray-500 mb-1">비고 및 건의사항</label>
							<textarea id={`${d}-en`} rows="2" bind:value={plan[d].event_note}
								class="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm focus:outline-none focus:border-primary-500 resize-y"></textarea>
						</div>
					</div>
				</div>
			{/each}
		</div>

		<div class="sticky bottom-4 mt-6 flex justify-end">
			<button type="button" onclick={save} disabled={saving}
				class="px-6 py-3 rounded-xl bg-primary-900 text-white font-bold text-sm shadow-lg hover:bg-primary-800 disabled:opacity-50">
				{saving ? '저장 중…' : `${dept} 계획 저장`}
			</button>
		</div>
	{/if}
</div>
