<script lang="ts">
    import { goto } from '$app/navigation';
    import { page } from '$app/stores';

    let { data } = $props();

    const selectedCategoryId = $derived(
        $page.url.searchParams.get('category') ? Number($page.url.searchParams.get('category')) : null
    );

    let searchQuery = $state('');

    const filteredVideos = $derived(
        data.videos
            .filter((v: { category_id: number }) => selectedCategoryId === null || v.category_id === selectedCategoryId)
            .filter((v: { title: string }) => !searchQuery || v.title.toLowerCase().includes(searchQuery.toLowerCase()))
    );

    function selectCategory(id: number | null) {
        const params = new URLSearchParams($page.url.searchParams);
        if (id === null) {
            params.delete('category');
        } else {
            params.set('category', String(id));
        }
        goto(`/videos?${params.toString()}`);
    }
</script>

<svelte:head>
    <title>영상 - 부평동부교회</title>
</svelte:head>

<div class="bg-gradient-to-b from-primary-50 to-white py-10 md:py-20 border-b border-gray-100">
    <div class="max-w-7xl mx-auto px-6 sm:px-8 lg:px-12 text-center animate-fade-in-up">
        <h1 class="text-3xl md:text-6xl font-black text-gray-900 mb-4 md:mb-8 tracking-tight font-serif drop-shadow-sm">
            영상
        </h1>
        <p class="text-base md:text-2xl text-gray-600 max-w-3xl mx-auto font-light leading-relaxed">
            예배 실황과 은혜로운 설교, 찬양을 영상으로 만나보세요.
        </p>
    </div>
</div>

<div class="w-full max-w-7xl mx-auto px-6 sm:px-8 lg:px-12 py-12 md:py-20">
    <!-- 카테고리 + 검색 -->
    <div class="flex flex-col md:flex-row items-center justify-between gap-4 mb-8 md:mb-16">
        <!-- 모바일: select -->
        <select
            class="md:hidden w-full px-4 py-3.5 rounded-2xl border-2 border-gray-200 bg-white font-bold text-gray-800 text-base focus:outline-none focus:border-primary-500 transition-colors"
            onchange={(e) => selectCategory((e.target as HTMLSelectElement).value === '' ? null : Number((e.target as HTMLSelectElement).value))}
        >
            <option value="" selected={selectedCategoryId === null}>전체</option>
            {#each data.categories as category}
                <option value={category.id} selected={selectedCategoryId === category.id}>{category.name}</option>
            {/each}
        </select>
        <!-- 데스크톱: 버튼 -->
        <div class="hidden md:flex items-center gap-3 py-1 px-0.5 shrink-0">
            <button
                type="button"
                class="whitespace-nowrap px-6 py-3 rounded-full text-lg font-bold transition-all duration-300 shadow-sm {selectedCategoryId === null
                    ? 'bg-primary-900 text-white shadow-lg scale-105'
                    : 'bg-white text-gray-600 border-2 border-gray-100 hover:border-primary-300 hover:text-primary-900'}"
                onclick={() => selectCategory(null)}
            >전체</button>
            {#each data.categories as category}
                <button
                    type="button"
                    class="whitespace-nowrap px-6 py-3 rounded-full text-lg font-bold transition-all duration-300 shadow-sm {selectedCategoryId === category.id
                        ? 'bg-primary-900 text-white shadow-lg scale-105'
                        : 'bg-white text-gray-600 border-2 border-gray-100 hover:border-primary-300 hover:text-primary-900'}"
                    onclick={() => selectCategory(category.id)}
                >{category.name}</button>
            {/each}
        </div>
        <div class="relative w-full md:w-72 shrink-0">
            <input
                type="text"
                bind:value={searchQuery}
                placeholder="영상 검색..."
                class="w-full pl-6 pr-14 py-3 rounded-full border-2 border-gray-200 focus:outline-none focus:border-primary-500 focus:ring-1 focus:ring-primary-500 transition-colors text-base"
            />
            <span class="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400">
                <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/>
                </svg>
            </span>
        </div>
    </div>

    {#if filteredVideos.length === 0}
        <div class="text-center py-20 text-gray-400 text-xl">영상이 없습니다.</div>
    {:else}
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-10">
            {#each filteredVideos as video}
                <a
                    href={video.youtubeUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="group flex flex-col bg-white rounded-3xl overflow-hidden shadow-sm hover:shadow-2xl transition-all duration-300 border border-gray-100 hover:-translate-y-2"
                >
                    <div class="relative aspect-video overflow-hidden bg-gray-100">
                        {#if video.thumbnail}
                            <img
                                src={video.thumbnail}
                                alt={video.title}
                                class="w-full h-full object-cover group-hover:scale-110 transition-transform duration-700"
                                onerror={(e) => {
                                    const img = e.currentTarget as HTMLImageElement;
                                    if (img.src.includes('maxresdefault')) {
                                        img.src = img.src.replace('maxresdefault', 'hqdefault');
                                    } else if (img.src.includes('hqdefault')) {
                                        img.src = img.src.replace('hqdefault', 'mqdefault');
                                    } else if (img.src.includes('mqdefault')) {
                                        img.src = img.src.replace('mqdefault', 'default');
                                    } else {
                                        img.style.display = 'none';
                                        const fallback = img.parentElement?.querySelector('.thumb-fallback') as HTMLElement;
                                        if (fallback) fallback.style.display = 'flex';
                                    }
                                }}
                            />
                        {/if}
                        <div class="thumb-fallback w-full h-full bg-gray-200 flex items-center justify-center absolute inset-0" style={video.thumbnail ? 'display:none' : ''}>
                            <svg class="w-12 h-12 text-gray-400" fill="currentColor" viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>
                        </div>
                        <div class="absolute inset-0 bg-black/20 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                            <div class="w-20 h-20 bg-white/95 rounded-full flex items-center justify-center backdrop-blur-sm shadow-xl transform group-hover:scale-110 transition-transform">
                                <svg class="w-10 h-10 text-primary-900 ml-2" fill="currentColor" viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>
                            </div>
                        </div>
                    </div>
                    <div class="p-5 md:p-8">
                        <div class="flex items-center text-sm font-bold text-primary-500 mb-3 md:mb-4 tracking-wide">
                            {video.category}
                            <span class="mx-3 text-gray-300">&bull;</span>
                            <span class="text-gray-500">{video.date}</span>
                        </div>
                        <h3 class="text-base md:text-xl font-bold text-gray-900 line-clamp-2 group-hover:text-primary-600 transition-colors leading-snug">
                            {video.title}
                        </h3>
                    </div>
                </a>
            {/each}
        </div>
    {/if}
</div>
