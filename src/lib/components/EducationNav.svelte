<script lang="ts">
	import { page } from '$app/stores';

	const tabs = [
		{ name: '보고서', href: '/education' },
		{ name: '월간 보고서', href: '/education/monthly' },
		{ name: '추이', href: '/education/trend' },
		{ name: '계획', href: '/education/plan' }
	];

	const current = $derived($page.url.pathname);

	function isActive(href: string): boolean {
		if (href === '/education') {
			// 목록(/education) 및 상세(/education/YYYY-MM-DD) 를 '보고서' 로 취급
			return (
				current === '/education' ||
				(current.startsWith('/education/') &&
					!current.startsWith('/education/trend') &&
					!current.startsWith('/education/plan') &&
					!current.startsWith('/education/monthly'))
			);
		}
		return current.startsWith(href);
	}
</script>

<div class="flex gap-1 mb-8 bg-gray-100 rounded-2xl p-1 w-fit">
	{#each tabs as t}
		<a
			href={t.href}
			class="px-4 py-2 rounded-xl text-sm font-bold transition-colors
			{isActive(t.href) ? 'bg-white text-primary-800 shadow-sm' : 'text-gray-500 hover:text-gray-800'}"
		>
			{t.name}
		</a>
	{/each}
</div>
