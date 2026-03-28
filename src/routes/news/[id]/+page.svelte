<script lang="ts">
    import { goto } from '$app/navigation';
    import { onMount } from 'svelte';
    import { supabaseBrowser } from '$lib/supabase-browser';

    let { data } = $props();
    const { post } = data;

    let canEdit = $state(false);
    let deleting = $state(false);

    onMount(async () => {
        const { data: { session } } = await supabaseBrowser.auth.getSession();
        if (!session) return;
        const { data: userInfo } = await supabaseBrowser
            .from('custom_users').select('roles(level)').eq('auth_id', session.user.id).single();
        const level = (userInfo?.roles as { level: number } | null)?.level ?? 0;
        canEdit = level >= 50;
    });

    async function handleDelete() {
        if (!confirm('게시물을 삭제하시겠습니까?')) return;
        deleting = true;
        await supabaseBrowser.from('posts').update({ active: false }).eq('id', post.id);
        goto('/news');
    }

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

<div class="w-full max-w-4xl mx-auto px-6 sm:px-8 lg:px-12 py-16">
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
        <div class="flex items-start justify-between gap-4 mb-4">
            <h1 class="text-3xl md:text-4xl font-black text-gray-900 leading-tight">
                {post.title}
            </h1>
            {#if canEdit}
                <div class="flex items-center gap-2 shrink-0">
                    <a href={`/news/${post.id}/edit`}
                        class="inline-flex items-center gap-1.5 px-4 py-2 rounded-full text-sm font-bold border-2 border-gray-200 text-gray-600 hover:border-primary-400 hover:text-primary-700 transition-colors">
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"/>
                        </svg>
                        수정
                    </a>
                    <button type="button" onclick={handleDelete} disabled={deleting}
                        class="inline-flex items-center gap-1.5 px-4 py-2 rounded-full text-sm font-bold border-2 border-gray-200 text-red-400 hover:border-red-300 hover:bg-red-50 transition-colors disabled:opacity-50">
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
                        </svg>
                        {deleting ? '삭제 중...' : '삭제'}
                    </button>
                </div>
            {/if}
        </div>
        <p class="text-gray-500 font-medium">{post.date}</p>
    </div>

    <!-- 본문 -->
    {#if post.content}
        {#if post.isHtml}
            <div class="prose prose-lg max-w-none text-gray-700 leading-relaxed mb-10 [&_img]:rounded-xl [&_img]:shadow-sm [&_img]:max-w-full [&_table]:w-full [&_table]:border-collapse [&_td]:p-2 [&_td]:border [&_td]:border-gray-200">
                {@html post.content}
            </div>
        {:else}
            <div class="prose prose-lg max-w-none text-gray-700 leading-relaxed whitespace-pre-wrap mb-10">
                {post.content}
            </div>
        {/if}
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

    <!-- 첨부파일 -->
    {#if post.attachments.length > 0}
        <div class="border border-gray-200 rounded-2xl p-6 bg-gray-50 {post.content || post.media_urls.length > 0 ? 'mt-10' : ''}">
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
