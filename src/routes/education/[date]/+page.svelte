<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { supabaseBrowser } from '$lib/supabase-browser';
	import {
		loadEducationAccess,
		DEPARTMENTS,
		blankRow,
		fmtFullDate,
		type EducationRow
	} from '$lib/education';

	type NumKey =
		| 'enrolled'
		| 'attend'
		| 'attend_online'
		| 'teacher_enrolled'
		| 'teacher_attend';
	type Fields = {
		enrolled: number | null;
		attend: number | null;
		attend_online: number | null;
		teacher_enrolled: number | null;
		teacher_attend: number | null;
		attendance_note: string;
		this_week: string;
		next_week: string;
		event_note: string;
	};

	const NUM_FIELDS: [NumKey, string][] = [
		['enrolled', '재적'],
		['attend', '출석'],
		['attend_online', '출석(on)'],
		['teacher_enrolled', '교사재적'],
		['teacher_attend', '교사출석']
	];

	const date = $page.params.date ?? '';
	const validDate = /^\d{4}-\d{2}-\d{2}$/.test(date);

	let loading = $state(true);
	let denied = $state(false);
	let isAdmin = $state(false);
	let editing = $state(false);
	let saving = $state(false);
	let msg = $state('');
	let existed = $state(false);
	let updatedAt = $state<string | null>(null);

	// 부서별 편집 필드. 뷰/편집 공용.
	let form = $state<Record<string, Fields>>({});
	let original: Record<string, Fields> = {};

	function fromRow(r: EducationRow): Fields {
		return {
			enrolled: r.enrolled,
			attend: r.attend,
			attend_online: r.attend_online,
			teacher_enrolled: r.teacher_enrolled,
			teacher_attend: r.teacher_attend,
			attendance_note: r.attendance_note ?? '',
			this_week: r.this_week ?? '',
			next_week: r.next_week ?? '',
			event_note: r.event_note ?? ''
		};
	}
	const toTxt = (s: string): string | null => (s.trim() === '' ? null : s.trim());

	onMount(async () => {
		if (!validDate) {
			denied = true;
			loading = false;
			return;
		}
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
		isAdmin = access.isAdmin;
		await load();
		if (!existed) editing = true; // 신규 주차는 바로 편집 모드
		loading = false;
	});

	async function load() {
		const { data } = await supabaseBrowser
			.from('education_reports')
			.select('*')
			.eq('report_date', date);
		const byDept = new Map<string, EducationRow>();
		let maxUpd: string | null = null;
		for (const r of (data ?? []) as EducationRow[]) {
			byDept.set(r.department, r);
			if (r.updated_at && (!maxUpd || r.updated_at > maxUpd)) maxUpd = r.updated_at;
		}
		existed = byDept.size > 0;
		updatedAt = maxUpd;

		// 전 주일 재적 캐리오버: 재적/교사재적이 비어 있으면 값이 있는 가장 최근 주의 값을 기본값으로 사용(수정 가능).
		const prevEnrolled = new Map<string, number>();
		const prevTeacher = new Map<string, number>();
		const { data: prior } = await supabaseBrowser
			.from('education_reports')
			.select('department, enrolled, teacher_enrolled')
			.lt('report_date', date)
			.order('report_date', { ascending: false });
		for (const r of (prior ?? []) as {
			department: string;
			enrolled: number | null;
			teacher_enrolled: number | null;
		}[]) {
			if (r.enrolled != null && !prevEnrolled.has(r.department)) prevEnrolled.set(r.department, r.enrolled);
			if (r.teacher_enrolled != null && !prevTeacher.has(r.department))
				prevTeacher.set(r.department, r.teacher_enrolled);
		}

		const next: Record<string, Fields> = {};
		for (const d of DEPARTMENTS) {
			const f = fromRow(byDept.get(d) ?? blankRow(date, d));
			if (f.enrolled === null && prevEnrolled.has(d)) f.enrolled = prevEnrolled.get(d) ?? null;
			if (f.teacher_enrolled === null && prevTeacher.has(d))
				f.teacher_enrolled = prevTeacher.get(d) ?? null;
			next[d] = f;
		}
		form = next;
		original = structuredClone(next);
	}

	function startEdit() {
		original = structuredClone($state.snapshot(form)) as Record<string, Fields>;
		editing = true;
		msg = '';
	}
	function cancelEdit() {
		form = structuredClone(original);
		editing = false;
		msg = '';
		if (!existed) goto('/education');
	}

	async function save() {
		saving = true;
		msg = '';
		const payload: EducationRow[] = DEPARTMENTS.map((d) => {
			const f = form[d];
			return {
				report_date: date,
				department: d,
				enrolled: f.enrolled ?? null,
				attend: f.attend ?? null,
				attend_online: f.attend_online ?? null,
				teacher_enrolled: f.teacher_enrolled ?? null,
				teacher_attend: f.teacher_attend ?? null,
				attendance_note: toTxt(f.attendance_note),
				this_week: toTxt(f.this_week),
				next_week: toTxt(f.next_week),
				event_note: toTxt(f.event_note)
			};
		});
		const { error } = await supabaseBrowser
			.from('education_reports')
			.upsert(payload, { onConflict: 'report_date,department' });
		saving = false;
		if (error) {
			msg = '저장 실패: ' + error.message;
			return;
		}
		await load();
		editing = false;
		msg = '저장되었습니다.';
	}

	async function removeWeek() {
		if (!confirm(`${fmtFullDate(date)} 보고서를 삭제할까요? 되돌릴 수 없습니다.`)) return;
		const { error } = await supabaseBrowser.from('education_reports').delete().eq('report_date', date);
		if (error) {
			msg = '삭제 실패: ' + error.message;
			return;
		}
		goto('/education');
	}

	// 총계(뷰용) — 현재 form 값 기준
	const totals = $derived.by(() => {
		const sum = { enrolled: 0, attend: 0, attend_online: 0, teacher_enrolled: 0, teacher_attend: 0 };
		for (const d of DEPARTMENTS) {
			const f = form[d];
			if (!f) continue;
			sum.enrolled += f.enrolled ?? 0;
			sum.attend += f.attend ?? 0;
			sum.attend_online += f.attend_online ?? 0;
			sum.teacher_enrolled += f.teacher_enrolled ?? 0;
			sum.teacher_attend += f.teacher_attend ?? 0;
		}
		return sum;
	});

	const numShow = (v: number | null) => (v === null || v === undefined ? '-' : String(v));
</script>

<svelte:head><title>교육부서 보고서 {date} - 부평동부교회</title></svelte:head>

<div class="w-full max-w-7xl mx-auto px-6 sm:px-8 lg:px-12 py-8 sm:py-12">
	<a href="/education" class="text-sm text-gray-400 hover:text-primary-600 font-medium">← 목록으로</a>

	{#if loading}
		<div class="py-20 text-center text-gray-400">불러오는 중…</div>
	{:else if denied}
		<div class="py-20 text-center">
			<p class="text-gray-500 font-medium">{validDate ? '접근 권한이 없습니다.' : '잘못된 날짜입니다.'}</p>
			<a href="/education" class="inline-block mt-6 px-6 py-2.5 rounded-full bg-primary-900 text-white font-bold text-sm">교육부서 보고서로</a>
		</div>
	{:else}
		<div class="flex items-start justify-between gap-3 mt-3 mb-1 flex-wrap">
			<div>
				<h1 class="text-2xl sm:text-3xl font-black text-gray-900">교육부서 보고서</h1>
				<p class="text-gray-500 text-sm mt-1">{fmtFullDate(date)}{#if !existed && !editing} · <span class="text-primary-600 font-semibold">신규</span>{/if}</p>
			</div>
			<div class="flex items-center gap-2">
				{#if editing}
					<button type="button" onclick={cancelEdit} disabled={saving}
						class="px-4 py-2 rounded-xl border-2 border-gray-200 text-gray-600 font-bold text-sm hover:bg-gray-50 disabled:opacity-50">취소</button>
					<button type="button" onclick={save} disabled={saving}
						class="px-5 py-2 rounded-xl bg-primary-900 text-white font-bold text-sm hover:bg-primary-800 disabled:opacity-50">{saving ? '저장 중…' : '저장'}</button>
				{:else}
					<button type="button" onclick={startEdit}
						class="px-5 py-2 rounded-xl bg-primary-900 text-white font-bold text-sm hover:bg-primary-800">수정</button>
				{/if}
			</div>
		</div>
		{#if updatedAt && !editing}
			<p class="text-[11px] text-gray-400 mb-4">최종 수정 {new Date(updatedAt).toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' })}</p>
		{/if}

		{#if msg}
			<div class="my-4 bg-primary-50 border border-primary-100 text-primary-800 text-sm rounded-xl px-4 py-3">{msg}</div>
		{/if}

		{#if !editing}
			<!-- ◎ 출석현황 -->
			<h2 class="text-base font-black text-gray-900 mt-6 mb-2">◎ 출석현황</h2>
			<div class="overflow-x-auto rounded-2xl border border-gray-300">
				<table class="w-full text-sm border-collapse min-w-[640px]">
					<thead>
						<tr class="bg-gray-50 text-gray-500 text-xs divide-x divide-gray-300 border-b border-gray-300">
							<th class="px-3 py-2.5 text-left font-bold">부서</th>
							<th class="px-3 py-2.5 font-bold">재적</th>
							<th class="px-3 py-2.5 font-bold">출석</th>
							<th class="px-3 py-2.5 font-bold">출석(on)</th>
							<th class="px-3 py-2.5 font-bold">교사재적</th>
							<th class="px-3 py-2.5 font-bold">교사출석</th>
							<th class="px-3 py-2.5 text-left font-bold">비고 및 새가족</th>
						</tr>
					</thead>
					<tbody>
						{#each DEPARTMENTS as d}
							<tr class="border-t border-gray-200 divide-x divide-gray-200">
								<td class="px-3 py-2.5 font-bold text-gray-900 whitespace-nowrap">{d}</td>
								<td class="px-3 py-2.5 text-center text-gray-700">{numShow(form[d].enrolled)}</td>
								<td class="px-3 py-2.5 text-center text-gray-900 font-semibold">{numShow(form[d].attend)}</td>
								<td class="px-3 py-2.5 text-center text-gray-500">{numShow(form[d].attend_online)}</td>
								<td class="px-3 py-2.5 text-center text-gray-700">{numShow(form[d].teacher_enrolled)}</td>
								<td class="px-3 py-2.5 text-center text-gray-700">{numShow(form[d].teacher_attend)}</td>
								<td class="px-3 py-2.5 text-gray-600 whitespace-pre-wrap">{form[d].attendance_note}</td>
							</tr>
						{/each}
						<tr class="border-t-2 border-gray-400 divide-x divide-gray-200 bg-gray-50 font-bold text-gray-900">
							<td class="px-3 py-2.5">총계</td>
							<td class="px-3 py-2.5 text-center">{totals.enrolled}</td>
							<td class="px-3 py-2.5 text-center">{totals.attend}</td>
							<td class="px-3 py-2.5 text-center">{totals.attend_online}</td>
							<td class="px-3 py-2.5 text-center">{totals.teacher_enrolled}</td>
							<td class="px-3 py-2.5 text-center">{totals.teacher_attend}</td>
							<td class="px-3 py-2.5"></td>
						</tr>
					</tbody>
				</table>
			</div>

			<!-- ◎ 교육 및 행사 -->
			<h2 class="text-base font-black text-gray-900 mt-8 mb-2">◎ 교육 및 행사</h2>
			<div class="overflow-x-auto rounded-2xl border border-gray-300">
				<!-- table-fixed + 명시 너비. '이번 주'·'다음 주'는 짧은 항목 위주라 좁게,
				     문장이 들어가는 '비고 및 건의사항'에 남은 폭을 몰아준다. -->
				<table class="w-full text-sm border-collapse table-fixed min-w-[720px]">
					<thead>
						<tr class="bg-gray-50 text-gray-500 text-xs divide-x divide-gray-300 border-b border-gray-300">
							<th class="px-3 py-2.5 text-left font-bold w-[80px]">부서</th>
							<th class="px-3 py-2.5 text-left font-bold w-[20%]">이번 주</th>
							<th class="px-3 py-2.5 text-left font-bold w-[20%]">다음 주</th>
							<th class="px-3 py-2.5 text-left font-bold">비고 및 건의사항</th>
						</tr>
					</thead>
					<tbody>
						{#each DEPARTMENTS as d}
							<tr class="border-t border-gray-200 divide-x divide-gray-200 align-top">
								<td class="px-3 py-2.5 font-bold text-gray-900 whitespace-nowrap">{d}</td>
								<td class="px-3 py-2.5 text-gray-700 whitespace-pre-wrap break-words">{form[d].this_week}</td>
								<td class="px-3 py-2.5 text-gray-700 whitespace-pre-wrap break-words">{form[d].next_week}</td>
								<td class="px-3 py-2.5 text-gray-600 whitespace-pre-wrap break-words">{form[d].event_note}</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>

			{#if isAdmin && existed}
				<div class="mt-10 text-right">
					<button type="button" onclick={removeWeek}
						class="text-xs font-bold text-red-400 hover:text-red-600 underline">이 보고서 삭제</button>
				</div>
			{/if}
		{:else}
			<!-- 편집: 부서별 카드 -->
			<p class="mt-6 mb-3 text-xs text-gray-400">재적·교사재적은 전 주일 값이 기본으로 채워집니다. 변동이 있으면 수정하세요.</p>
			<div class="space-y-4">
				{#each DEPARTMENTS as d}
					<div class="rounded-2xl border border-gray-200 p-4 sm:p-5">
						<h3 class="font-black text-gray-900 mb-3">{d}</h3>
						<div class="grid grid-cols-2 sm:grid-cols-5 gap-3 mb-3">
							{#each NUM_FIELDS as [key, label]}
								<div>
									<label for={`${d}-${key}`} class="block text-[11px] font-bold text-gray-500 mb-1">{label}</label>
									<input id={`${d}-${key}`} type="number" min="0" inputmode="numeric"
										bind:value={form[d][key]}
										class="w-full px-2.5 py-2 rounded-lg border border-gray-200 text-sm text-center focus:outline-none focus:border-primary-500" />
								</div>
							{/each}
						</div>
						<div class="mb-3">
							<label for={`${d}-anote`} class="block text-[11px] font-bold text-gray-500 mb-1">비고 및 새가족</label>
							<textarea id={`${d}-anote`} rows="2" bind:value={form[d].attendance_note}
								class="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm focus:outline-none focus:border-primary-500 resize-y"></textarea>
						</div>
						<div class="grid sm:grid-cols-2 gap-3 mb-3">
							<div>
								<label for={`${d}-tw`} class="block text-[11px] font-bold text-gray-500 mb-1">이번 주</label>
								<textarea id={`${d}-tw`} rows="2" bind:value={form[d].this_week}
									class="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm focus:outline-none focus:border-primary-500 resize-y"></textarea>
							</div>
							<div>
								<label for={`${d}-nw`} class="block text-[11px] font-bold text-gray-500 mb-1">다음 주</label>
								<textarea id={`${d}-nw`} rows="2" bind:value={form[d].next_week}
									class="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm focus:outline-none focus:border-primary-500 resize-y"></textarea>
							</div>
						</div>
						<div>
							<label for={`${d}-enote`} class="block text-[11px] font-bold text-gray-500 mb-1">비고 및 건의사항</label>
							<textarea id={`${d}-enote`} rows="2" bind:value={form[d].event_note}
								class="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm focus:outline-none focus:border-primary-500 resize-y"></textarea>
						</div>
					</div>
				{/each}
			</div>
		{/if}
	{/if}
</div>
