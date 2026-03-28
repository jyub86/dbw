<script lang="ts">
    import { goto } from '$app/navigation';
    import { page } from '$app/stores';
    import { onMount } from 'svelte';
    import { supabaseBrowser } from '$lib/supabase-browser';

    let { data } = $props();
    let searchInput = $state(data.search);
    let isManager = $state(false);

    onMount(async () => {
        const { data: { session } } = await supabaseBrowser.auth.getSession();
        if (!session) return;
        const { data: userInfo } = await supabaseBrowser
            .from('custom_users')
            .select('roles(level)')
            .eq('auth_id', session.user.id)
            .single();
        const level = (userInfo?.roles as { level: number } | null)?.level ?? 0;
        isManager = level >= 50;
    });

    function buildUrl(params: Record<string, string | null>) {
        const p = new URLSearchParams($page.url.searchParams);
        for (const [k, v] of Object.entries(params)) {
            if (v === null) p.delete(k);
            else p.set(k, v);
        }
        return `/news?${p.toString()}`;
    }

    function selectCategory(label: string | null) {
        goto(buildUrl({ category: label, page: '1' }));
    }

    function submitSearch(e: Event) {
        e.preventDefault();
        goto(buildUrl({ search: searchInput || null, page: '1' }));
    }

    function goPage(p: number) {
        goto(buildUrl({ page: String(p) }));
    }

    const pageNumbers = $derived(() => {
        const range = [];
        const start = Math.max(1, data.page - 2);
        const end = Math.min(data.totalPages, data.page + 2);
        for (let i = start; i <= end; i++) range.push(i);
        return range;
    });
</script>

<svelte:head>
    <title>교회 소식 - 부평동부교회</title>
</svelte:head>

<div class="bg-gray-50 py-12 md:py-32 border-b border-gray-200">
    <div class="max-w-7xl mx-auto px-6 sm:px-8 lg:px-12 text-center">
        <h1 class="text-3xl md:text-6xl font-black text-gray-900 mb-4 md:mb-8 tracking-tight">
            교회 소식
        </h1>
        <p class="text-base md:text-xl text-gray-600 max-w-3xl mx-auto leading-relaxed">
            부평동부교회의 다양한 소식과 자료를 확인하실 수 있습니다.
        </p>
    </div>
</div>

<div class="w-full max-w-6xl mx-auto px-6 sm:px-8 lg:px-12 py-12 md:py-20">
    <!-- 카테고리 + 검색 -->
    <div class="flex flex-col md:flex-row items-center justify-between gap-4 mb-8 md:mb-12">
        <div class="flex items-center gap-3 overflow-x-auto no-scrollbar py-1 px-0.5 w-full md:w-auto shrink-0">
            <button
                type="button"
                class="whitespace-nowrap shrink-0 px-6 py-3 rounded-full text-base md:text-lg font-bold transition-all duration-300 shadow-sm {data.categoryParam === null ? 'bg-primary-900 text-white shadow-lg scale-105' : 'bg-white text-gray-600 border-2 border-gray-100 hover:border-primary-300 hover:text-primary-900'}"
                onclick={() => selectCategory(null)}
            >전체</button>
            {#each data.filterCategories as label}
                <button
                    type="button"
                    class="whitespace-nowrap shrink-0 px-6 py-3 rounded-full text-base md:text-lg font-bold transition-all duration-300 shadow-sm {data.categoryParam === label ? 'bg-primary-900 text-white shadow-lg scale-105' : 'bg-white text-gray-600 border-2 border-gray-100 hover:border-primary-300 hover:text-primary-900'}"
                    onclick={() => selectCategory(label)}
                >{label}</button>
            {/each}
        </div>
        <div class="flex items-center gap-3 w-full md:w-auto">
            <div class="relative grow md:w-72 shrink-0">
                <form onsubmit={submitSearch}>
                    <input
                        type="text"
                        bind:value={searchInput}
                        placeholder="게시물 검색..."
                        class="w-full pl-6 pr-14 py-3 rounded-full border-2 border-gray-200 focus:outline-none focus:border-primary-500 focus:ring-1 focus:ring-primary-500 transition-colors text-base"
                    />
                    <button type="submit" class="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 hover:text-primary-600">
                        <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/>
                        </svg>
                    </button>
                </form>
            </div>
            {#if isManager}
                <a
                    href="/news/write"
                    class="shrink-0 px-6 py-3 bg-primary-900 text-white font-bold rounded-full hover:bg-primary-800 transition-colors text-base whitespace-nowrap"
                >
                    글쓰기
                </a>
            {/if}
        </div>
    </div>

    {#if data.news.length === 0}
        <div class="text-center py-20 text-gray-400 text-xl">게시물이 없습니다.</div>
    {:else}
        <div class="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
            <div class="divide-y divide-gray-100">
                {#each data.news as item}
                    <a
                        href={`/news/${item.id}`}
                        class="block hover:bg-gray-50 transition-colors p-6 md:p-8"
                    >
                        <div class="flex flex-col md:flex-row gap-2 md:gap-4 md:items-center justify-between">
                            <div class="flex items-center gap-3 md:gap-6 overflow-hidden">
                                <span class="shrink-0 px-3 py-1.5 md:px-4 md:py-2 bg-primary-50 text-primary-700 text-xs md:text-base font-bold rounded-lg border border-primary-100 w-20 md:w-24 text-center">
                                    {item.category}
                                </span>
                                <h3 class="text-base md:text-2xl font-semibold text-gray-900 transition-colors line-clamp-1">
                                    {item.title}
                                </h3>
                                {#if item.isNew}
                                    <span class="hidden md:inline-flex items-center px-2.5 py-1 rounded text-xs font-black bg-red-100 text-red-600 uppercase tracking-widest">New</span>
                                {/if}
                            </div>
                            <div class="flex items-center gap-2 text-sm md:text-base text-gray-500 font-medium md:ml-auto md:shrink-0">
                                <svg class="w-4 h-4 md:w-5 md:h-5 text-gray-400 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"></path>
                                </svg>
                                {item.date}
                            </div>
                        </div>
                    </a>
                {/each}
            </div>
        </div>

        <!-- 페이지네이션 -->
        {#if data.totalPages > 1}
            <div class="flex justify-center mt-16">
                <nav class="inline-flex rounded-full shadow-sm">
                    <button
                        onclick={() => goPage(data.page - 1)}
                        disabled={data.page <= 1}
                        class="relative inline-flex items-center px-4 py-3 rounded-l-full border-y border-l border-gray-300 bg-white text-gray-500 hover:bg-gray-50 font-bold disabled:opacity-40 disabled:cursor-not-allowed"
                    >이전</button>
                    {#each pageNumbers() as p}
                        <button
                            onclick={() => goPage(p)}
                            class="relative inline-flex items-center px-6 py-3 border text-lg font-bold {p === data.page
                                ? 'z-10 bg-primary-600 border-primary-600 text-white'
                                : 'bg-white border-gray-300 text-gray-700 hover:bg-gray-50'}"
                        >{p}</button>
                    {/each}
                    <button
                        onclick={() => goPage(data.page + 1)}
                        disabled={data.page >= data.totalPages}
                        class="relative inline-flex items-center px-4 py-3 rounded-r-full border border-gray-300 bg-white text-gray-500 hover:bg-gray-50 font-bold disabled:opacity-40 disabled:cursor-not-allowed"
                    >다음</button>
                </nav>
            </div>
        {/if}
    {/if}
</div>
