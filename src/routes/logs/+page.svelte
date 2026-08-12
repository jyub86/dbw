<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { supabaseBrowser } from '$lib/supabase-browser';
	import {
		loadIsAdmin,
		TABLE_LABELS,
		FEATURES,
		opLabel,
		opClass,
		fieldLabel,
		fmtVal,
		type AuditLog
	} from '$lib/audit';

	const PAGE = 50;

	let loading = $state(true);
	let denied = $state(false);
	let logs = $state<AuditLog[]>([]);
	let feature = $state('all');
	let search = $state('');
	let from = $state(0);
	let done = $state(false);
	let fetching = $state(false);

	onMount(async () => {
		const { hasSession, isAdmin } = await loadIsAdmin();
		if (!hasSession) {
			goto('/login');
			return;
		}
		if (!isAdmin) {
			denied = true;
			loading = false;
			return;
		}
		await reload();
		loading = false;
	});

	function buildQuery(fromIdx: number) {
		let q = supabaseBrowser
			.from('audit_logs')
			.select('*')
			.order('changed_at', { ascending: false })
			.range(fromIdx, fromIdx + PAGE - 1);
		const f = FEATURES.find((x) => x.key === feature);
		if (f && f.tables.length) q = q.in('table_name', f.tables);
		const term = search.trim();
		if (term) q = q.ilike('actor_name', `%${term}%`);
		return q;
	}

	async function reload() {
		fetching = true;
		from = 0;
		done = false;
		const { data } = await buildQuery(0);
		logs = (data ?? []) as AuditLog[];
		from = logs.length;
		done = logs.length < PAGE;
		fetching = false;
	}

	async function loadMore() {
		if (fetching || done) return;
		fetching = true;
		const { data } = await buildQuery(from);
		const rows = (data ?? []) as AuditLog[];
		logs = [...logs, ...rows];
		from += rows.length;
		done = rows.length < PAGE;
		fetching = false;
	}

	function fmtTime(iso: string): string {
		return new Date(iso).toLocaleString('ko-KR', {
			timeZone: 'Asia/Seoul',
			month: 'numeric',
			day: 'numeric',
			hour: '2-digit',
			minute: '2-digit'
		});
	}

	// 로그 1건의 변경 상세 라인들
	function diffLines(log: AuditLog): { field: string; before: string; after: string }[] {
		const out: { field: string; before: string; after: string }[] = [];
		if (log.operation === 'UPDATE' && log.changed_fields) {
			for (const f of log.changed_fields) {
				out.push({
					field: fieldLabel(f),
					before: fmtVal(log.old_data?.[f]),
					after: fmtVal(log.new_data?.[f])
				});
			}
		}
		return out;
	}

	// INSERT/DELETE 요약(메모·이름 등 핵심 값)
	function summaryLine(log: AuditLog): string {
		const d = log.operation === 'DELETE' ? log.old_data : log.new_data;
		if (!d) return '';
		if (typeof d.note === 'string' && d.note.trim()) return fmtVal(d.note);
		if (typeof d.present === 'boolean') return d.present ? '출석' : '결석';
		if (typeof d.role === 'string') return fmtVal(d.role);
		return '';
	}
</script>

<svelte:head><title>변경 로그 - 부평동부교회</title></svelte:head>

<div class="w-full max-w-7xl mx-auto px-6 sm:px-8 lg:px-12 py-10 sm:py-14">
	<h1 class="text-2xl sm:text-3xl font-black text-gray-900 mb-1">변경 로그</h1>
	<p class="text-gray-500 mb-6 text-sm sm:text-base">누가 언제 무엇을 수정했는지 기록입니다. (관리자 전용)</p>

	{#if loading}
		<div class="py-20 text-center text-gray-400">불러오는 중…</div>
	{:else if denied}
		<div class="py-20 text-center">
			<p class="text-gray-500 font-medium">접근 권한이 없습니다.</p>
			<a href="/" class="inline-block mt-6 px-6 py-2.5 rounded-full bg-primary-900 text-white font-bold text-sm">홈으로</a>
		</div>
	{:else}
		<!-- 필터 -->
		<div class="flex flex-wrap items-center gap-2 mb-5">
			<div class="flex gap-1.5">
				{#each FEATURES as f}
					<button type="button" onclick={() => { feature = f.key; reload(); }}
						class="px-3.5 py-2 rounded-xl text-sm font-bold border-2 transition-colors {feature === f.key ? 'bg-primary-900 text-white border-primary-900' : 'border-gray-200 text-gray-600 hover:border-primary-400'}">
						{f.label}
					</button>
				{/each}
			</div>
			<input type="text" placeholder="이름으로 검색" bind:value={search}
				onkeydown={(e) => { if (e.key === 'Enter') reload(); }}
				class="flex-1 min-w-[140px] px-3 py-2 rounded-xl border-2 border-gray-200 text-sm focus:outline-none focus:border-primary-500" />
			<button type="button" onclick={reload}
				class="px-4 py-2 rounded-xl bg-gray-900 text-white font-bold text-sm hover:bg-gray-700">검색</button>
		</div>

		{#if logs.length === 0}
			<div class="py-16 text-center text-gray-400 text-sm">기록이 없습니다.</div>
		{:else}
			<div class="space-y-2.5">
				{#each logs as log}
					<div class="rounded-2xl border border-gray-100 px-4 py-3">
						<div class="flex items-center gap-2 flex-wrap">
							<span class="text-[11px] font-bold px-2 py-0.5 rounded {opClass(log.operation)}">{opLabel(log.operation)}</span>
							<span class="text-xs font-bold text-gray-500">{TABLE_LABELS[log.table_name] ?? log.table_name}</span>
							<span class="font-bold text-gray-900 text-sm">{log.target_label ?? ''}</span>
							<span class="ml-auto text-[11px] text-gray-400">{fmtTime(log.changed_at)}</span>
						</div>

						{#if diffLines(log).length}
							<div class="mt-2 space-y-0.5">
								{#each diffLines(log) as ln}
									<div class="text-xs text-gray-600">
										<span class="text-gray-400">{ln.field}</span>
										<span class="mx-1 text-gray-400 line-through">{ln.before}</span>
										<span class="text-gray-400">→</span>
										<span class="ml-1 font-semibold text-gray-800">{ln.after}</span>
									</div>
								{/each}
							</div>
						{:else if summaryLine(log)}
							<div class="mt-1.5 text-xs text-gray-600 whitespace-pre-wrap">{summaryLine(log)}</div>
						{/if}

						<div class="mt-1.5 text-[11px] text-gray-400">by {log.actor_name ?? '시스템'}</div>
					</div>
				{/each}
			</div>

			{#if !done}
				<div class="mt-6 text-center">
					<button type="button" onclick={loadMore} disabled={fetching}
						class="px-6 py-2.5 rounded-full border-2 border-gray-200 text-gray-600 font-bold text-sm hover:bg-gray-50 disabled:opacity-50">
						{fetching ? '불러오는 중…' : '더 보기'}
					</button>
				</div>
			{/if}
		{/if}
	{/if}
</div>
