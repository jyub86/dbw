<script lang="ts">
    import { goto } from '$app/navigation';
    import { page } from '$app/stores';

    let { data } = $props();

    let searchInput = $state(data.search);

    function buildUrl(params: Record<string, string | null>) {
        const p = new URLSearchParams($page.url.searchParams);
        for (const [k, v] of Object.entries(params)) {
            if (v === null) p.delete(k);
            else p.set(k, v);
        }
        return `/board?${p.toString()}`;
    }

    function selectCategory(id: number | null) {
        goto(buildUrl({ category: id !== null ? String(id) : null, page: '1' }));
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
    <title>게시판 - 부평동부교회</title>
</svelte:head>

<div class="bg-gray-50 py-20 md:py-32 border-b border-gray-200">
    <div class="max-w-7xl mx-auto px-6 sm:px-8 lg:px-12 text-center">
        <h1 class="text-4xl md:text-6xl font-black text-gray-900 mb-8 tracking-tight">게시판</h1>
        <p class="text-xl text-gray-600 max-w-3xl mx-auto leading-relaxed">
            성도님들 간의 자유로운 교제와 나눔을 위한 공간입니다.
        </p>
    </div>
</div>

<div class="w-full max-w-6xl mx-auto px-6 sm:px-8 lg:px-12 py-20">

    <!-- 카테고리 + 검색 -->
    <div class="flex flex-col md:flex-row items-center justify-between gap-4 mb-12">
        <div class="flex flex-wrap items-center gap-3">
            <button
                type="button"
                class="px-6 py-3 rounded-full text-base md:text-lg font-bold transition-all duration-300 shadow-sm {data.categoryId === null ? 'bg-primary-900 text-white shadow-lg scale-105' : 'bg-white text-gray-600 border-2 border-gray-100 hover:border-primary-300 hover:text-primary-900'}"
                onclick={() => selectCategory(null)}
            >전체</button>
            {#each data.categories as cat}
                <button
                    type="button"
                    class="px-6 py-3 rounded-full text-base md:text-lg font-bold transition-all duration-300 shadow-sm {data.categoryId === cat.id ? 'bg-primary-900 text-white shadow-lg scale-105' : 'bg-white text-gray-600 border-2 border-gray-100 hover:border-primary-300 hover:text-primary-900'}"
                    onclick={() => selectCategory(cat.id)}
                >{cat.name}</button>
            {/each}
        </div>
        <div class="relative w-full md:w-72 shrink-0">
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
    </div>

    <!-- 목록 -->
    {#if data.posts.length === 0}
        <div class="text-center py-20 text-gray-400 text-xl">게시물이 없습니다.</div>
    {:else}
        <div class="w-full bg-white rounded-3xl shadow-sm border border-gray-100 overflow-hidden text-lg">
            <div class="hidden md:grid grid-cols-12 gap-6 p-6 md:p-8 bg-gray-50 border-b border-gray-200 font-bold text-gray-700 text-center">
                <div class="col-span-1">번호</div>
                <div class="col-span-1">분류</div>
                <div class="col-span-6 text-left pl-4">제목</div>
                <div class="col-span-2">작성자</div>
                <div class="col-span-2">작성일</div>
            </div>

            <div class="divide-y divide-gray-100">
                {#each data.posts as post, index}
                    <a href={`/board/${post.id}`} class="block hover:bg-gray-50 transition-colors">
                        <div class="flex flex-col md:grid md:grid-cols-12 gap-4 md:gap-6 p-6 md:p-8 items-center text-center">
                            <div class="hidden md:block col-span-1 text-gray-400 font-medium">
                                {data.totalCount - ((data.page - 1) * 20 + index)}
                            </div>
                            <div class="hidden md:flex col-span-1 justify-center">
                                <span class="px-2 py-1 bg-primary-50 text-primary-700 text-xs font-bold rounded-lg border border-primary-100 truncate max-w-full">
                                    {post.category_id === 9 ? '1401' : '게시판'}
                                </span>
                            </div>
                            <div class="col-span-6 text-left w-full pl-0 md:pl-4">
                                <div class="flex items-center gap-3">
                                    <span class="md:hidden px-2 py-1 bg-primary-50 text-primary-700 text-xs font-bold rounded">
                                        {post.category_id === 9 ? '1401' : '게시판'}
                                    </span>
                                    <h3 class="text-xl md:text-2xl font-bold text-gray-900 truncate">
                                        {post.title}
                                    </h3>
                                </div>
                            </div>
                            <div class="col-span-5 md:contents flex items-center justify-between w-full mt-3 md:mt-0 text-base md:text-lg text-gray-500 font-medium border-t border-gray-100 md:border-0 pt-3 md:pt-0">
                                <div class="md:col-span-2 flex items-center justify-center gap-2">
                                    <span class="md:hidden text-gray-400">작성자</span>
                                    {post.author}
                                </div>
                                <div class="md:col-span-2 flex items-center justify-center gap-2">
                                    {post.date}
                                </div>
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
