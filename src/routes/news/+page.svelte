<script lang="ts">
    let { data } = $props();

    const PAGE_SIZE = 20;
    let limit = $state(PAGE_SIZE);
    let activeBoard = $state<number | null>(null);
    let searchQuery = $state('');

    const filteredNews = $derived(
        data.news
            .filter((n: { category_id: number }) => activeBoard === null || n.category_id === activeBoard)
            .filter((n: { title: string }) => !searchQuery || n.title.toLowerCase().includes(searchQuery.toLowerCase()))
    );

    const visibleNews = $derived(filteredNews.slice(0, limit));
    const hasMore = $derived(filteredNews.length > limit);

    function selectCategory(id: number | null) {
        activeBoard = id;
        limit = PAGE_SIZE;
    }
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
            부평동부교회의 다양한 소식과 주보를 확인하실 수 있습니다.
        </p>
    </div>
</div>

<div class="w-full max-w-6xl mx-auto px-6 sm:px-8 lg:px-12 py-12 md:py-20">
    <!-- 카테고리 + 검색 -->
    <div class="flex flex-col md:flex-row items-center justify-between gap-4 mb-8 md:mb-12">
        <div class="flex items-center gap-3 overflow-x-auto no-scrollbar py-1 px-0.5 w-full md:w-auto shrink-0">
            <button
                type="button"
                class="whitespace-nowrap shrink-0 px-6 py-3 rounded-full text-base md:text-lg font-bold transition-all duration-300 shadow-sm {activeBoard === null ? 'bg-primary-900 text-white shadow-lg scale-105' : 'bg-white text-gray-600 border-2 border-gray-100 hover:border-primary-300 hover:text-primary-900'}"
                onclick={() => selectCategory(null)}
            >전체</button>
            {#each data.categories as category}
                <button
                    type="button"
                    class="whitespace-nowrap shrink-0 px-6 py-3 rounded-full text-base md:text-lg font-bold transition-all duration-300 shadow-sm {activeBoard === category.id ? 'bg-primary-900 text-white shadow-lg scale-105' : 'bg-white text-gray-600 border-2 border-gray-100 hover:border-primary-300 hover:text-primary-900'}"
                    onclick={() => selectCategory(category.id)}
                >{category.name}</button>
            {/each}
        </div>
        <div class="relative w-full md:w-72 shrink-0">
            <input
                type="text"
                bind:value={searchQuery}
                placeholder="게시물 검색..."
                class="w-full pl-6 pr-14 py-3 rounded-full border-2 border-gray-200 focus:outline-none focus:border-primary-500 focus:ring-1 focus:ring-primary-500 transition-colors text-base"
            />
            <span class="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400">
                <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/>
                </svg>
            </span>
        </div>
    </div>

    {#if visibleNews.length === 0}
        <div class="text-center py-20 text-gray-400 text-xl">게시물이 없습니다.</div>
    {:else}
        <div class="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
            <div class="divide-y divide-gray-100">
                {#each visibleNews as item}
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

        {#if hasMore}
            <div class="flex justify-center mt-16">
                <button
                    onclick={() => limit += PAGE_SIZE}
                    class="px-10 py-4 bg-white border-2 border-gray-200 text-gray-700 font-bold rounded-full text-lg hover:border-primary-500 hover:text-primary-600 transition-colors shadow-sm"
                >
                    더보기 ▾
                </button>
            </div>
        {/if}
    {/if}
</div>
