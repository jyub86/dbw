<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { supabaseBrowser } from '$lib/supabase-browser';
	import {
		loadEducationAccess,
		fmtShort,
		fmtFullDate,
		sundayList,
		thisSunday,
		halfKey,
		halfLabel,
		currentHalfKey
	} from '$lib/education';
	import EducationNav from '$lib/components/EducationNav.svelte';

	type WeekSummary = {
		date: string;
		enrolled: number;
		attend: number;
		teacherEnrolled: number;
		teacherAttend: number;
	};
	type Profile = { id: string; name: string | null; office: string | null; phone: string | null; active?: boolean };
	type Editor = { user_id: string; note: string | null; custom_users: { name: string | null; office: string | null } | null };

	let loading = $state(true);
	let denied = $state(false);
	let isAdmin = $state(false);
	let msg = $state('');

	let weeks = $state<WeekSummary[]>([]);
	let newDate = $state(thisSunday());
	const sundayOptions = sundayList(6, 12); // 미래 12주 → 과거 6주

	// 반기별 접힘/펼침 (현재 반기만 기본 펼침)
	let openHalves = $state<Record<string, boolean>>({});

	// 담당자 지정 (관리자만)
	let editors = $state<Editor[]>([]);
	let edPickerOpen = $state(false);
	let edQuery = $state('');
	let edResults = $state<Profile[]>([]);

	type HalfGroup = { key: string; label: string; weeks: WeekSummary[] };
	const halfGroups = $derived.by<HalfGroup[]>(() => {
		const map = new Map<string, WeekSummary[]>();
		for (const w of weeks) {
			const k = halfKey(w.date);
			const arr = map.get(k);
			if (arr) arr.push(w);
			else map.set(k, [w]);
		}
		return [...map.entries()]
			.map(([key, ws]) => ({ key, label: halfLabel(ws[0].date), weeks: ws }))
			.sort((a, b) => (a.key < b.key ? 1 : -1));
	});

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
		isAdmin = access.isAdmin;

		await loadWeeks();
		openHalves = { [currentHalfKey()]: true }; // 현재 반기만 펼침
		if (isAdmin) await loadEditors();
		loading = false;
	});

	async function loadWeeks() {
		const { data } = await supabaseBrowser
			.from('education_reports')
			.select('report_date, enrolled, attend, teacher_enrolled, teacher_attend')
			.order('report_date', { ascending: false });
		const map = new Map<string, WeekSummary>();
		for (const r of data ?? []) {
			const w = map.get(r.report_date) ?? {
				date: r.report_date,
				enrolled: 0,
				attend: 0,
				teacherEnrolled: 0,
				teacherAttend: 0
			};
			w.enrolled += r.enrolled ?? 0;
			w.attend += r.attend ?? 0;
			w.teacherEnrolled += r.teacher_enrolled ?? 0;
			w.teacherAttend += r.teacher_attend ?? 0;
			map.set(r.report_date, w);
		}
		weeks = [...map.values()].sort((a, b) => (a.date < b.date ? 1 : -1));
	}

	function rate(w: WeekSummary): number {
		return w.enrolled > 0 ? Math.round((w.attend / w.enrolled) * 100) : 0;
	}

	function openNew() {
		if (!newDate) return;
		goto(`/education/${newDate}`);
	}

	// ── 담당자 지정 ───────────────────────────────
	async function loadEditors() {
		const { data } = await supabaseBrowser
			.from('education_report_editors')
			.select('user_id, note, custom_users(name, office)');
		editors = (data ?? []) as unknown as Editor[];
	}
	async function searchProfiles(q: string) {
		const term = q.trim();
		if (term.length < 1) {
			edResults = [];
			return;
		}
		const { data } = await supabaseBrowser
			.from('custom_users')
			.select('id, name, office, phone, active')
			.ilike('name', `%${term}%`)
			.order('active', { ascending: false })
			.order('name')
			.limit(30);
		edResults = (data ?? []) as Profile[];
	}
	async function addEditor(pid: string) {
		const { error } = await supabaseBrowser.from('education_report_editors').insert({ user_id: pid });
		msg = error ? '담당자 지정 실패 (관리자만 가능)' : '담당자로 지정되었습니다.';
		edPickerOpen = false;
		edQuery = '';
		edResults = [];
		await loadEditors();
	}
	async function removeEditor(pid: string) {
		const { error } = await supabaseBrowser.from('education_report_editors').delete().eq('user_id', pid);
		if (error) msg = '해제 실패 (관리자만 가능)';
		await loadEditors();
	}
</script>

<svelte:head><title>교육부서 보고서 - 부평동부교회</title></svelte:head>

<div class="w-full max-w-4xl mx-auto px-5 sm:px-8 py-10 sm:py-14">
	<h1 class="text-2xl sm:text-3xl font-black text-gray-900 mb-1">교육부서 보고서</h1>
	<p class="text-gray-500 mb-6 text-sm sm:text-base">주간 부서별 출석현황과 교육·행사를 기록합니다.</p>

	<EducationNav />

	{#if msg}
		<div class="mb-5 bg-primary-50 border border-primary-100 text-primary-800 text-sm rounded-xl px-4 py-3">{msg}</div>
	{/if}

	{#if loading}
		<div class="py-20 text-center text-gray-400">불러오는 중…</div>
	{:else if denied}
		<div class="py-20 text-center">
			<p class="text-gray-500 font-medium">접근 권한이 없습니다.</p>
			<a href="/" class="inline-block mt-6 px-6 py-2.5 rounded-full bg-primary-900 text-white font-bold text-sm">홈으로</a>
		</div>
	{:else}
		<!-- 새 보고서 작성 (주일만 선택) -->
		<div class="mb-8 flex items-end gap-3 flex-wrap rounded-2xl border border-gray-100 bg-gray-50 px-4 py-4">
			<div>
				<label for="nd" class="block text-xs font-bold text-gray-600 mb-1.5">보고 주일 선택</label>
				<select id="nd" bind:value={newDate}
					class="px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium text-sm">
					{#each sundayOptions as s}
						<option value={s}>{fmtFullDate(s)}{s === thisSunday() ? ' (이번 주)' : ''}</option>
					{/each}
				</select>
			</div>
			<button type="button" onclick={openNew}
				class="px-5 py-2.5 rounded-xl bg-primary-900 text-white font-bold text-sm hover:bg-primary-800">보고서 작성/열기</button>
		</div>

		<!-- 주간 목록 (반기별) -->
		{#if weeks.length === 0}
			<div class="py-16 text-center text-gray-400 text-sm">아직 작성된 보고서가 없습니다.</div>
		{:else}
			{#each halfGroups as g}
				<div class="mb-4">
					<button type="button" onclick={() => (openHalves[g.key] = !openHalves[g.key])}
						class="w-full flex items-center justify-between px-4 py-3 rounded-2xl border border-gray-100 bg-white hover:border-primary-300 transition-colors">
						<span class="font-black text-gray-900">{g.label}</span>
						<span class="text-sm text-gray-400 font-bold">{g.weeks.length}주 <span class="ml-1 text-gray-300">{openHalves[g.key] ? '▲' : '▼'}</span></span>
					</button>
					{#if openHalves[g.key]}
						<div class="grid gap-3 sm:grid-cols-2 mt-3">
							{#each g.weeks as w}
								<a href={`/education/${w.date}`}
									class="group rounded-2xl border border-gray-100 hover:border-primary-300 hover:shadow-sm transition-all px-5 py-4 bg-white">
									<div class="flex items-baseline justify-between">
										<span class="text-lg font-black text-gray-900">{fmtShort(w.date)}</span>
										<span class="text-[11px] text-gray-400">{fmtFullDate(w.date)}</span>
									</div>
									<div class="mt-2 flex items-center gap-4 text-sm">
										<span class="text-gray-500">학생 <b class="text-gray-900">{w.attend}</b>/{w.enrolled}</span>
										<span class="text-primary-700 font-bold">{rate(w)}%</span>
										<span class="text-gray-400 text-xs">교사 {w.teacherAttend}/{w.teacherEnrolled}</span>
									</div>
								</a>
							{/each}
						</div>
					{/if}
				</div>
			{/each}
		{/if}

		<!-- 담당자 지정 (관리자만) -->
		{#if isAdmin}
			<section class="mt-14">
				<div class="flex items-center justify-between mb-3">
					<h2 class="text-lg font-black text-gray-900">보고서 담당자 지정</h2>
					<button type="button" onclick={() => { edPickerOpen = !edPickerOpen; edQuery=''; edResults=[]; }}
						class="px-4 py-2 rounded-xl bg-gray-900 text-white font-bold text-sm hover:bg-gray-700">+ 담당자 추가</button>
				</div>
				<p class="text-xs text-gray-400 mb-3">지정된 담당자는 <b>교육부서 보고서를 열람·수정</b>할 수 있습니다. (추가/해제는 관리자만 가능)</p>

				{#if edPickerOpen}
					<div class="rounded-2xl border border-gray-200 p-4 mb-4 bg-gray-50">
						<input type="text" placeholder="이름으로 검색" bind:value={edQuery} oninput={() => searchProfiles(edQuery)}
							class="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm focus:outline-none focus:border-primary-500 mb-2" />
						<div class="max-h-56 overflow-y-auto divide-y divide-gray-100 bg-white rounded-lg">
							{#each edResults as r}
								<button type="button" onclick={() => addEditor(r.id)} class="w-full text-left px-3 py-2 hover:bg-primary-50 text-sm flex justify-between">
									<span class="font-medium">{r.name}{#if r.active === false}<span class="ml-1 text-[10px] text-gray-400 font-normal">(미가입)</span>{/if}</span>
									<span class="text-gray-400 text-xs">{r.office} · {r.phone || '번호없음'}</span>
								</button>
							{/each}
							{#if edQuery && edResults.length === 0}<div class="px-3 py-3 text-sm text-gray-400">검색 결과 없음</div>{/if}
						</div>
					</div>
				{/if}

				<div class="rounded-2xl border border-gray-100 overflow-hidden">
					{#if editors.length === 0}
						<div class="px-4 py-5 text-sm text-gray-400 text-center">지정된 담당자가 없습니다.</div>
					{/if}
					{#each editors as ed}
						<div class="flex items-center justify-between px-4 py-3 border-b border-gray-50 last:border-0">
							<div>
								<span class="font-bold text-gray-900">{ed.custom_users?.name ?? '(이름없음)'}</span>
								<span class="text-xs text-gray-400 ml-2">{ed.custom_users?.office ?? ''}{ed.note ? ` · ${ed.note}` : ''}</span>
							</div>
							<button type="button" onclick={() => removeEditor(ed.user_id)} class="px-2.5 py-1.5 rounded-lg text-xs font-bold border border-red-200 text-red-500 hover:bg-red-50">해제</button>
						</div>
					{/each}
				</div>
			</section>
		{/if}
	{/if}
</div>
