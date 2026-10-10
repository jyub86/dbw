<script lang="ts">
    import { page } from '$app/stores';
    import type { RegistryMe } from '$lib/registry';

    let { me }: { me: RegistryMe } = $props();

    const current = $derived($page.url.pathname);
    const tabs = $derived(
        [
            // 교적 카드(/registry/<id>)도 '교인 목록' 아래로 본다
            { name: '교인 목록', href: '/registry', show: me.is_staff,
              on: current === '/registry' || /^\/registry\/[0-9a-f-]{36}/.test(current) },
            { name: '새가족 등록', href: '/registry/new', show: me.is_staff && me.can_edit, on: current === '/registry/new' },
            { name: '확인 목록', href: '/registry/candidates', show: me.is_staff, on: current === '/registry/candidates' },
            { name: '권한·기록', href: '/registry/admin', show: me.is_admin, on: current === '/registry/admin' }
        ].filter((t) => t.show)
    );
</script>

{#if tabs.length > 1}
    <div class="flex flex-wrap gap-1 mb-8 bg-gray-100 rounded-2xl p-1 w-fit">
        {#each tabs as t}
            <a href={t.href}
                class="px-4 py-2 rounded-xl text-sm font-bold transition-colors {t.on ? 'bg-white text-primary-800 shadow-sm' : 'text-gray-500 hover:text-gray-800'}">
                {t.name}
            </a>
        {/each}
    </div>
{/if}
