<script lang="ts">
    let { data } = $props();
    const { post } = data;

    function getYouTubeId(url: string): string | null {
        const patterns = [
            /youtube\.com\/watch\?.*v=([^&#]+)/,
            /youtu\.be\/([^?&#]+)/,
            /youtube\.com\/embed\/([^?&#]+)/,
            /youtube\.com\/shorts\/([^?&#]+)/,
        ];
        for (const p of patterns) {
            const m = url.match(p);
            if (m) return m[1];
        }
        return null;
    }

    function isImageUrl(url: string): boolean {
        return /\.(jpe?g|png|gif|webp|bmp|svg)(\?.*)?$/i.test(url);
    }
</script>

<svelte:head>
    <title>{post.title} - 부평동부교회</title>
</svelte:head>

<div class="w-full max-w-4xl mx-auto px-6 sm:px-8 lg:px-12 py-16">
    <!-- 뒤로가기 -->
    <a href="/board" class="inline-flex items-center gap-2 text-gray-500 hover:text-primary-600 font-medium mb-10 transition-colors">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/>
        </svg>
        게시판으로 돌아가기
    </a>

    <!-- 헤더 -->
    <div class="border-b border-gray-200 pb-8 mb-10">
        <span class="inline-block px-4 py-1.5 bg-primary-50 text-primary-700 text-sm font-bold rounded-lg border border-primary-100 mb-4">
            {post.category}
        </span>
        <h1 class="text-3xl md:text-4xl font-black text-gray-900 leading-tight mb-6">
            {post.title}
        </h1>
        <div class="flex items-center gap-3">
            <div class="w-9 h-9 rounded-full bg-gray-200 overflow-hidden flex items-center justify-center shrink-0">
                {#if post.authorProfile}
                    <img src={post.authorProfile} alt={post.author} class="w-full h-full object-cover" />
                {:else}
                    <svg class="w-5 h-5 text-gray-400" fill="currentColor" viewBox="0 0 24 24">
                        <path d="M12 12c2.7 0 4.8-2.1 4.8-4.8S14.7 2.4 12 2.4 7.2 4.5 7.2 7.2 9.3 12 12 12zm0 2.4c-3.2 0-9.6 1.6-9.6 4.8v2.4h19.2v-2.4c0-3.2-6.4-4.8-9.6-4.8z"/>
                    </svg>
                {/if}
            </div>
            <div>
                <p class="font-bold text-gray-900">{post.author}</p>
                <p class="text-sm text-gray-400">{post.date}</p>
            </div>
        </div>
    </div>

    <!-- 본문 -->
    {#if post.content}
        <div class="text-gray-700 text-lg leading-relaxed whitespace-pre-wrap mb-10">
            {post.content}
        </div>
    {/if}

    <!-- 미디어 -->
    {#if post.media_urls.length > 0}
        <div class="space-y-6">
            {#each post.media_urls as url}
                {#if getYouTubeId(url)}
                    <div class="relative w-full rounded-2xl overflow-hidden shadow-sm border border-gray-100" style="aspect-ratio: 16/9;">
                        <iframe
                            src={`https://www.youtube.com/embed/${getYouTubeId(url)}`}
                            title="YouTube 영상"
                            class="absolute inset-0 w-full h-full"
                            frameborder="0"
                            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                            allowfullscreen
                        ></iframe>
                    </div>
                {:else if isImageUrl(url)}
                    <img src={url} alt={post.title} class="w-full rounded-2xl shadow-sm border border-gray-100" />
                {:else}
                    <a href={url} target="_blank" rel="noopener noreferrer"
                        class="flex items-center gap-3 p-4 bg-gray-50 rounded-2xl border border-gray-200 hover:border-primary-300 transition-colors group">
                        <svg class="w-5 h-5 text-gray-400 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"/>
                        </svg>
                        <span class="text-sm text-gray-600 truncate group-hover:text-primary-600 transition-colors">{url}</span>
                        <svg class="w-4 h-4 text-gray-400 shrink-0 ml-auto" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"/>
                        </svg>
                    </a>
                {/if}
            {/each}
        </div>
    {/if}

    {#if !post.content && post.media_urls.length === 0}
        <p class="text-center text-gray-400 py-20">내용이 없습니다.</p>
    {/if}
</div>
