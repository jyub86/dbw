<script lang="ts">
    let { data } = $props();
    const { post } = data;
</script>

<svelte:head>
    <title>{post.title} - 부평동부교회</title>
</svelte:head>

<div class="max-w-4xl mx-auto px-6 sm:px-8 lg:px-12 py-16">
    <!-- 뒤로가기 -->
    <a href="/news" class="inline-flex items-center gap-2 text-gray-500 hover:text-primary-600 font-medium mb-10 transition-colors">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/>
        </svg>
        교회 소식으로 돌아가기
    </a>

    <!-- 헤더 -->
    <div class="border-b border-gray-200 pb-8 mb-10">
        <span class="inline-block px-4 py-1.5 bg-primary-50 text-primary-700 text-sm font-bold rounded-lg border border-primary-100 mb-4">
            {post.category}
        </span>
        <h1 class="text-3xl md:text-4xl font-black text-gray-900 leading-tight mb-4">
            {post.title}
        </h1>
        <p class="text-gray-500 font-medium">{post.date}</p>
    </div>

    <!-- 본문 -->
    {#if post.content}
        <div class="prose prose-lg max-w-none text-gray-700 leading-relaxed whitespace-pre-wrap">
            {post.content}
        </div>
    {/if}

    <!-- 이미지 (주보 등) -->
    {#if post.media_urls.length > 0}
        <div class="space-y-6 {post.content ? 'mt-10' : ''}">
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
