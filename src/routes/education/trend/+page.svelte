<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { supabaseBrowser } from '$lib/supabase-browser';
	import { loadEducationAccess, DEPARTMENTS, fmtFullDate, fmtShort } from '$lib/education';
	import EducationNav from '$lib/components/EducationNav.svelte';

	type RawRow = {
		report_date: string;
		department: string;
		enrolled: number | null;
		attend: number | null;
	};
	type Point = { date: string; enrolled: number; attend: number; rate: number };

	let loading = $state(true);
	let denied = $state(false);
	let rows = $state<RawRow[]>([]);
	let dept = $state<'all' | string>('all');

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
		const { data } = await supabaseBrowser
			.from('education_reports')
			.select('report_date, department, enrolled, attend')
			.order('report_date', { ascending: true });
		rows = (data ?? []) as RawRow[];
		loading = false;
	});

	// 선택 부서(또는 전체 합계) 기준 주별 출석률. 출석이 기록된 주(attend>0)만 표시.
	const points = $derived.by<Point[]>(() => {
		const byDate = new Map<string, { enrolled: number; attend: number }>();
		for (const r of rows) {
			if (dept !== 'all' && r.department !== dept) continue;
			const cur = byDate.get(r.report_date) ?? { enrolled: 0, attend: 0 };
			cur.enrolled += r.enrolled ?? 0;
			cur.attend += r.attend ?? 0;
			byDate.set(r.report_date, cur);
		}
		return [...byDate.entries()]
			.map(([date, v]) => ({
				date,
				enrolled: v.enrolled,
				attend: v.attend,
				rate: v.enrolled > 0 ? Math.round((v.attend / v.enrolled) * 100) : 0
			}))
			.filter((p) => p.attend > 0)
			.sort((a, b) => (a.date < b.date ? -1 : 1));
	});

	const avgRate = $derived(
		points.length ? Math.round(points.reduce((s, p) => s + p.rate, 0) / points.length) : 0
	);
	const scopeLabel = $derived(dept === 'all' ? '전체' : dept);
</script>

<svelte:head><title>교육부서 추이 - 부평동부교회</title></svelte:head>

<div class="w-full max-w-7xl mx-auto px-6 sm:px-8 lg:px-12 py-10 sm:py-14">
	<h1 class="text-2xl sm:text-3xl font-black text-gray-900 mb-1">교육부서 추이</h1>
	<p class="text-gray-500 mb-6 text-sm sm:text-base">부서별 주간 출석률 변화를 살펴봅니다.</p>

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
		<div class="flex items-center gap-2 mb-5 flex-wrap">
			<select bind:value={dept}
				class="px-4 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium text-sm">
				<option value="all">전체</option>
				{#each DEPARTMENTS as d}<option value={d}>{d}</option>{/each}
			</select>
			<span class="text-sm text-gray-400">평균 출석률 <b class="text-primary-700">{avgRate}%</b></span>
		</div>

		<h2 class="text-base font-black text-gray-900 mb-3">{scopeLabel} · 주간 출석률 추이</h2>

		{#if points.length === 0}
			<p class="text-gray-400 text-sm">표시할 데이터가 없습니다.</p>
		{:else}
			<div class="rounded-2xl border border-gray-100 bg-white p-4 overflow-x-auto">
				<div class="flex items-end gap-2 min-w-fit" style="height:200px">
					{#each points as p}
						<div class="flex flex-col items-center gap-1 w-12 shrink-0 justify-end">
							<span class="text-[10px] font-bold text-gray-500">{p.rate}%</span>
							<div class="w-7 bg-gray-100 rounded-t-md flex items-end" style="height:150px">
								<div class="w-full bg-primary-500 rounded-t-md transition-all" style="height:{Math.max(p.rate * 1.5, 4)}px"></div>
							</div>
							<span class="text-[9px] text-gray-400 text-center leading-tight">{fmtShort(p.date)}</span>
						</div>
					{/each}
				</div>
			</div>

			<div class="rounded-2xl border border-gray-100 bg-white divide-y divide-gray-50 mt-4">
				{#each [...points].reverse() as p}
					<div class="flex items-center justify-between px-4 py-2.5 text-sm">
						<span class="font-medium text-gray-800">{fmtFullDate(p.date)}</span>
						<span class="text-gray-500">{p.attend}/{p.enrolled}명</span>
						<span class="font-bold text-primary-700 w-14 text-right">{p.rate}%</span>
					</div>
				{/each}
			</div>
			<p class="text-xs text-gray-400 mt-2">※ 출석률 = 출석 ÷ 재적. 출석이 입력된 주만 표시됩니다.</p>
		{/if}
	{/if}
</div>
