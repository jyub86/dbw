<script lang="ts">
    import { page } from '$app/stores';

    let { canManage = false }: { canManage?: boolean } = $props();

    const tabs = $derived([
        { name: '출석 체크', href: '/attendance', show: true },
        { name: '통계 대시보드', href: '/attendance/dashboard', show: canManage },
        { name: '명단 관리', href: '/attendance/manage', show: canManage }
    ].filter((t) => t.show));

    const current = $derived($page.url.pathname);
</script>

{#if tabs.length > 1}
    <div class="flex gap-1 mb-8 bg-gray-100 rounded-2xl p-1 w-fit">
        {#each tabs as t}
            <a
                href={t.href}
                class="px-4 py-2 rounded-xl text-sm font-bold transition-colors
                {current === t.href ? 'bg-white text-primary-800 shadow-sm' : 'text-gray-500 hover:text-gray-800'}"
            >
                {t.name}
            </a>
        {/each}
    </div>
{/if}
