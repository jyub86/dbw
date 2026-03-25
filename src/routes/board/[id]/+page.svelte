<script lang="ts">
    let { data } = $props();
    const { post } = data;
</script>

<svelte:head>
    <title>{post.title} - 부평동부교회</title>
</svelte:head>

<div class="max-w-4xl mx-auto px-6 sm:px-8 lg:px-12 py-16">
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

    <!-- 이미지 -->
    {#if post.media_urls.length > 0}
        <div class="space-y-4">
            {#each post.media_urls as url}
                <img
                    src={url}
                    alt={post.title}
                    class="w-full rounded-2xl shadow-sm border border-gray-100"
                />
            {/each}
        </div>
    {/if}

    {#if !post.content && post.media_urls.length === 0}
        <p class="text-center text-gray-400 py-20">내용이 없습니다.</p>
    {/if}
</div>
