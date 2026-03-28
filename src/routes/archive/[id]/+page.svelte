<script lang="ts">
    let { data } = $props();
    const { post } = data;

    function getFileIcon(filename: string) {
        const ext = filename.split('.').pop()?.toLowerCase() ?? '';
        if (ext === 'pdf') return '📄';
        if (['hwp', 'doc', 'docx'].includes(ext)) return '📝';
        if (['xls', 'xlsx'].includes(ext)) return '📊';
        if (['jpg', 'jpeg', 'png', 'gif'].includes(ext)) return '🖼️';
        return '📎';
    }
</script>

<svelte:head>
    <title>{post.title} - 부평동부교회</title>
</svelte:head>

<div class="max-w-4xl mx-auto px-6 sm:px-8 lg:px-12 py-16">
    <!-- 뒤로가기 -->
    <a href="/archive" class="inline-flex items-center gap-2 text-gray-500 hover:text-primary-600 font-medium mb-10 transition-colors">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/>
        </svg>
        이전 자료로 돌아가기
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
        {#if post.isHtml}
            <!-- HTML 콘텐츠 (구역공과, 선교소식 등 이미지 포함 게시물) -->
            <div class="prose prose-lg max-w-none text-gray-700 leading-relaxed mb-10 [&_img]:rounded-xl [&_img]:shadow-sm [&_img]:max-w-full [&_table]:w-full [&_table]:border-collapse [&_td]:p-2 [&_td]:border [&_td]:border-gray-200">
                {@html post.content}
            </div>
        {:else}
            <!-- 일반 텍스트 콘텐츠 -->
            <div class="text-gray-700 text-lg leading-relaxed whitespace-pre-wrap mb-10">
                {post.content}
            </div>
        {/if}
    {/if}

    <!-- 이미지 (media_urls) -->
    {#if post.media_urls.length > 0}
        <div class="space-y-4 mb-10">
            {#each post.media_urls as url}
                <img
                    src={url}
                    alt={post.title}
                    class="w-full rounded-2xl shadow-sm border border-gray-100"
                />
            {/each}
        </div>
    {/if}

    <!-- 첨부파일 -->
    {#if post.attachments.length > 0}
        <div class="border border-gray-200 rounded-2xl p-6 bg-gray-50">
            <h3 class="font-bold text-gray-700 mb-4 text-base flex items-center gap-2">
                <svg class="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.172 7l-6.586 6.586a2 2 0 102.828 2.828l6.414-6.586a4 4 0 00-5.656-5.656l-6.415 6.585a6 6 0 108.486 8.486L20.5 13"/>
                </svg>
                첨부파일 ({post.attachments.length}개)
            </h3>
            <ul class="space-y-2">
                {#each post.attachments as att}
                    <li>
                        <a
                            href={att.url}
                            target="_blank"
                            rel="noopener noreferrer"
                            download
                            class="inline-flex items-center gap-3 px-4 py-3 bg-white border border-gray-200 rounded-xl hover:border-primary-300 hover:bg-primary-50 transition-colors group w-full"
                        >
                            <span class="text-xl">{getFileIcon(att.name)}</span>
                            <span class="text-gray-700 group-hover:text-primary-700 font-medium text-sm truncate flex-1">
                                {att.name}
                            </span>
                            <svg class="w-4 h-4 text-gray-400 group-hover:text-primary-600 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"/>
                            </svg>
                        </a>
                    </li>
                {/each}
            </ul>
        </div>
    {/if}

    {#if !post.content && post.media_urls.length === 0 && post.attachments.length === 0}
        <p class="text-center text-gray-400 py-20">내용이 없습니다.</p>
    {/if}
</div>
