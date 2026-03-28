<script lang="ts">
    import { goto } from '$app/navigation';
    import { onMount } from 'svelte';
    import { supabaseBrowser } from '$lib/supabase-browser';

    let { data } = $props();

    let title = $state(data.post.title);
    let content = $state(data.post.content);
    let categoryId = $state<number>(data.post.category_id);
    let submitting = $state(false);
    let submitLabel = $state('저장하기');
    let error = $state('');
    let authChecked = $state(false);
    let userLevel = $state(0);

    const MANAGER_LEVEL = 50;
    const MANAGER_ONLY_CATEGORY_IDS = [9];

    const availableCategories = $derived(
        data.categories.filter((cat: { id: number; name: string }) =>
            !MANAGER_ONLY_CATEGORY_IDS.includes(cat.id) || userLevel >= MANAGER_LEVEL
        )
    );

    // 기존 미디어 URL (삭제 표시 가능)
    let existingUrls = $state<string[]>([...data.post.media_urls]);

    // 새 이미지 첨부
    type NewImage = { file: File; previewUrl: string };
    let newImages = $state<NewImage[]>([]);
    let fileInput = $state<HTMLInputElement | null>(null);
    let isDraggingImage = $state(false);

    // 새 외부 URL
    type UrlItem = { url: string; type: 'youtube' | 'image' | 'other' };
    let newUrls = $state<UrlItem[]>([]);
    let urlInput = $state('');
    let urlError = $state('');

    const MAX_WIDTH = 1920;
    const MAX_HEIGHT = 1080;
    const MAX_NEW_IMAGES = 10;
    const MAX_NEW_URLS = 10;

    onMount(async () => {
        const { data: { session } } = await supabaseBrowser.auth.getSession();
        if (!session) { goto('/login'); return; }
        if (session.user.id !== data.post.user_id) { goto(`/board/${data.post.id}`); return; }

        const { data: userInfo } = await supabaseBrowser
            .from('custom_users').select('roles(level)').eq('auth_id', session.user.id).single();
        userLevel = (userInfo?.roles as { level: number } | null)?.level ?? 0;
        authChecked = true;
    });

    // ── URL 유틸 ──────────────────────────────────────────
    function getYouTubeId(url: string): string | null {
        const patterns = [
            /youtube\.com\/watch\?.*v=([^&#]+)/,
            /youtu\.be\/([^?&#]+)/,
            /youtube\.com\/embed\/([^?&#]+)/,
            /youtube\.com\/shorts\/([^?&#]+)/,
        ];
        for (const p of patterns) { const m = url.match(p); if (m) return m[1]; }
        return null;
    }
    function isImageUrl(url: string) { return /\.(jpe?g|png|gif|webp|bmp|svg)(\?.*)?$/i.test(url); }
    function detectUrlType(url: string): UrlItem['type'] {
        if (getYouTubeId(url)) return 'youtube';
        if (isImageUrl(url)) return 'image';
        return 'other';
    }

    function addNewUrl() {
        urlError = '';
        const trimmed = urlInput.trim();
        if (!trimmed) return;
        try { new URL(trimmed); } catch { urlError = '올바른 URL을 입력해주세요.'; return; }
        if ([...existingUrls, ...newUrls.map(u => u.url)].includes(trimmed)) { urlError = '이미 추가된 URL입니다.'; return; }
        if (newUrls.length >= MAX_NEW_URLS) { urlError = `URL은 최대 ${MAX_NEW_URLS}개까지 추가할 수 있습니다.`; return; }
        newUrls = [...newUrls, { url: trimmed, type: detectUrlType(trimmed) }];
        urlInput = '';
    }
    function handleUrlKeydown(e: KeyboardEvent) { if (e.key === 'Enter') { e.preventDefault(); addNewUrl(); } }

    // ── 이미지 ────────────────────────────────────────────
    function resizeImage(file: File): Promise<Blob> {
        return new Promise((resolve) => {
            const img = new Image();
            const objectUrl = URL.createObjectURL(file);
            img.onload = () => {
                URL.revokeObjectURL(objectUrl);
                let { width, height } = img;
                if (width <= MAX_WIDTH && height <= MAX_HEIGHT) { resolve(file); return; }
                const ratio = Math.min(MAX_WIDTH / width, MAX_HEIGHT / height);
                width = Math.round(width * ratio); height = Math.round(height * ratio);
                const canvas = document.createElement('canvas');
                canvas.width = width; canvas.height = height;
                canvas.getContext('2d')!.drawImage(img, 0, 0, width, height);
                canvas.toBlob((blob) => resolve(blob!), 'image/jpeg', 0.92);
            };
            img.src = objectUrl;
        });
    }

    function addNewImages(files: File[]) {
        for (const file of files.slice(0, MAX_NEW_IMAGES - newImages.length)) {
            if (!file.type.startsWith('image/')) continue;
            newImages = [...newImages, { file, previewUrl: URL.createObjectURL(file) }];
        }
    }
    function handleFileChange(e: Event) {
        const input = e.target as HTMLInputElement;
        addNewImages(Array.from(input.files ?? []));
        input.value = '';
    }
    function handleImageDrop(e: DragEvent) { e.preventDefault(); isDraggingImage = false; addNewImages(Array.from(e.dataTransfer?.files ?? [])); }
    function handleImageDragOver(e: DragEvent) { e.preventDefault(); isDraggingImage = true; }
    function handleImageDragLeave(e: DragEvent) { if (!(e.currentTarget as Element).contains(e.relatedTarget as Node)) isDraggingImage = false; }
    function removeNewImage(i: number) { URL.revokeObjectURL(newImages[i].previewUrl); newImages = newImages.filter((_, j) => j !== i); }

    // ── 저장 ──────────────────────────────────────────────
    async function handleSubmit(e: Event) {
        e.preventDefault();
        if (!title.trim()) { error = '제목을 입력해주세요.'; return; }
        if (MANAGER_ONLY_CATEGORY_IDS.includes(categoryId) && userLevel < MANAGER_LEVEL) {
            error = '해당 분류는 매니저 이상만 작성할 수 있습니다.'; return;
        }

        submitting = true; error = '';

        const { data: { session } } = await supabaseBrowser.auth.getSession();
        if (!session) { goto('/login'); return; }

        const mediaUrls = [...existingUrls];

        if (newImages.length > 0) {
            for (let i = 0; i < newImages.length; i++) {
                submitLabel = `이미지 업로드 중... (${i + 1}/${newImages.length})`;
                const blob = await resizeImage(newImages[i].file);
                const path = `${session.user.id}/posts_${data.post.id}_edit_${Date.now()}_${i + 1}.jpg`;
                const { error: uploadErr } = await supabaseBrowser.storage
                    .from('posts').upload(path, blob, { contentType: 'image/jpeg', upsert: true });
                if (uploadErr) continue;
                const { data: urlData } = supabaseBrowser.storage.from('posts').getPublicUrl(path);
                if (urlData?.publicUrl) mediaUrls.push(urlData.publicUrl);
            }
        }

        for (const u of newUrls) mediaUrls.push(u.url);

        submitLabel = '저장 중...';
        const { error: updateErr } = await supabaseBrowser
            .from('posts')
            .update({ title: title.trim(), content: content.trim(), category_id: categoryId, media_urls: mediaUrls })
            .eq('id', data.post.id);

        if (updateErr) {
            error = '저장에 실패했습니다. 다시 시도해주세요.';
            submitting = false; submitLabel = '저장하기'; return;
        }

        goto(`/board/${data.post.id}`);
    }
</script>

<svelte:head>
    <title>게시물 수정 - 부평동부교회</title>
</svelte:head>

{#if authChecked}
<div class="w-full max-w-6xl mx-auto px-6 sm:px-8 lg:px-12 py-16">
    <a href={`/board/${data.post.id}`} class="inline-flex items-center gap-2 text-gray-500 hover:text-primary-600 font-medium mb-10 transition-colors">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/>
        </svg>
        게시물로 돌아가기
    </a>

    <h1 class="text-3xl md:text-4xl font-black text-gray-900 mb-10">게시물 수정</h1>

    <form onsubmit={handleSubmit} class="space-y-7">
        <!-- 분류 -->
        <div>
            <label for="category" class="block text-sm font-bold text-gray-700 mb-2">분류</label>
            <select id="category" bind:value={categoryId}
                class="w-full sm:w-48 px-4 py-3 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 transition-colors text-base font-medium bg-white">
                {#each availableCategories as cat}
                    <option value={cat.id}>{cat.name}</option>
                {/each}
            </select>
        </div>

        <!-- 제목 -->
        <div>
            <label for="title" class="block text-sm font-bold text-gray-700 mb-2">제목</label>
            <input id="title" type="text" bind:value={title} placeholder="제목을 입력하세요" maxlength="200"
                class="w-full px-4 py-3 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 transition-colors text-base" />
        </div>

        <!-- 내용 -->
        <div>
            <label for="content" class="block text-sm font-bold text-gray-700 mb-2">내용</label>
            <textarea id="content" bind:value={content} placeholder="내용을 입력하세요" rows="16"
                class="w-full px-4 py-3 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 transition-colors text-base resize-none leading-relaxed"></textarea>
        </div>

        <!-- 기존 미디어 -->
        {#if existingUrls.length > 0}
        <div>
            <label class="block text-sm font-bold text-gray-700 mb-3">
                첨부된 미디어 <span class="text-gray-400 font-normal">— 삭제할 항목을 제거하세요</span>
            </label>
            <div class="space-y-2">
                {#each existingUrls as url, i}
                    <div class="flex items-center gap-3 p-3 bg-gray-50 rounded-xl border border-gray-100 group">
                        {#if getYouTubeId(url)}
                            <img src={`https://img.youtube.com/vi/${getYouTubeId(url)}/mqdefault.jpg`} alt="썸네일"
                                class="shrink-0 w-20 h-12 object-cover rounded-lg border border-gray-100" />
                        {:else if isImageUrl(url)}
                            <img src={url} alt="이미지" class="shrink-0 w-20 h-12 object-cover rounded-lg border border-gray-100" />
                        {:else}
                            <div class="shrink-0 w-10 h-10 rounded-lg bg-gray-100 flex items-center justify-center">
                                <svg class="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"/>
                                </svg>
                            </div>
                        {/if}
                        <span class="flex-1 text-sm text-gray-600 truncate min-w-0">{url}</span>
                        <button type="button" onclick={() => existingUrls = existingUrls.filter((_, j) => j !== i)}
                            class="shrink-0 w-7 h-7 rounded-full text-gray-400 hover:bg-red-50 hover:text-red-500 flex items-center justify-center transition-colors opacity-0 group-hover:opacity-100">
                            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M6 18L18 6M6 6l12 12"/>
                            </svg>
                        </button>
                    </div>
                {/each}
            </div>
        </div>
        {/if}

        <!-- 새 이미지 추가 -->
        <div>
            <div class="flex items-center justify-between mb-3">
                <label class="text-sm font-bold text-gray-700">
                    이미지 추가 <span class="text-gray-400 font-normal">({newImages.length}/{MAX_NEW_IMAGES})</span>
                </label>
                {#if newImages.length > 0 && newImages.length < MAX_NEW_IMAGES}
                    <button type="button" onclick={() => fileInput?.click()}
                        class="inline-flex items-center gap-1.5 px-4 py-2 rounded-full text-sm font-bold border-2 border-gray-200 text-gray-600 hover:border-primary-400 hover:text-primary-700 transition-colors">
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
                        </svg>
                        이미지 추가
                    </button>
                {/if}
            </div>
            <input type="file" accept="image/*" multiple bind:this={fileInput} onchange={handleFileChange} class="hidden" />
            <div role="region" aria-label="이미지 드롭존"
                ondrop={handleImageDrop} ondragover={handleImageDragOver} ondragleave={handleImageDragLeave}
                class="relative rounded-2xl transition-all duration-150 {isDraggingImage ? 'ring-2 ring-primary-400' : ''}">
                {#if isDraggingImage}
                    <div class="absolute inset-0 rounded-2xl border-2 border-dashed border-primary-400 bg-primary-50/90 flex items-center justify-center z-10 pointer-events-none">
                        <div class="flex flex-col items-center gap-2 text-primary-600">
                            <svg class="w-10 h-10" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                            </svg>
                            <span class="font-bold text-base">이미지를 여기에 놓으세요</span>
                        </div>
                    </div>
                {/if}
                {#if newImages.length === 0}
                    <button type="button" onclick={() => fileInput?.click()}
                        class="w-full border-2 border-dashed rounded-2xl py-10 flex flex-col items-center gap-3 transition-colors {isDraggingImage ? 'border-primary-400 text-primary-500 bg-primary-50' : 'border-gray-200 text-gray-400 hover:border-primary-300 hover:text-primary-500'}">
                        <svg class="w-9 h-9" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                        </svg>
                        <span class="text-sm font-medium">클릭하거나 드래그 앤 드롭으로 이미지 추가</span>
                        <span class="text-xs">최대 {MAX_NEW_IMAGES}장 · 1920×1080 초과 시 자동 리사이즈</span>
                    </button>
                {:else}
                    <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 gap-3">
                        {#each newImages as img, i}
                            <div class="relative group aspect-square rounded-xl overflow-hidden border-2 border-gray-100 bg-gray-50">
                                <img src={img.previewUrl} alt={`새 이미지 ${i + 1}`} class="w-full h-full object-cover" />
                                <button type="button" onclick={() => removeNewImage(i)}
                                    class="absolute top-1.5 right-1.5 w-6 h-6 rounded-full bg-black/60 text-white flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity hover:bg-red-500">
                                    <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M6 18L18 6M6 6l12 12"/>
                                    </svg>
                                </button>
                            </div>
                        {/each}
                        {#if newImages.length < MAX_NEW_IMAGES}
                            <button type="button" onclick={() => fileInput?.click()}
                                class="aspect-square rounded-xl border-2 border-dashed border-gray-200 flex flex-col items-center justify-center gap-2 text-gray-400 hover:border-primary-300 hover:text-primary-500 transition-colors">
                                <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
                                </svg>
                                <span class="text-xs font-medium">추가</span>
                            </button>
                        {/if}
                    </div>
                {/if}
            </div>
        </div>

        <!-- 새 URL 추가 -->
        <div>
            <label class="block text-sm font-bold text-gray-700 mb-3">
                URL 추가 <span class="text-gray-400 font-normal">— 이미지 또는 YouTube 영상</span>
            </label>
            <div class="flex gap-2 mb-3">
                <input type="url" bind:value={urlInput} onkeydown={handleUrlKeydown} placeholder="https://..."
                    class="flex-1 px-4 py-3 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 transition-colors text-base" />
                <button type="button" onclick={addNewUrl}
                    class="shrink-0 px-5 py-3 bg-gray-900 text-white font-bold rounded-xl hover:bg-gray-700 transition-colors text-sm">
                    추가
                </button>
            </div>
            {#if urlError}<p class="text-red-500 text-xs font-medium mb-3">{urlError}</p>{/if}
            {#if newUrls.length > 0}
                <div class="space-y-2">
                    {#each newUrls as item, i}
                        <div class="flex items-center gap-3 p-3 bg-gray-50 rounded-xl border border-gray-100 group">
                            {#if item.type === 'youtube'}
                                <img src={`https://img.youtube.com/vi/${getYouTubeId(item.url)}/mqdefault.jpg`} alt="썸네일"
                                    class="shrink-0 w-20 h-12 object-cover rounded-lg border border-gray-100" />
                            {:else if item.type === 'image'}
                                <img src={item.url} alt="미리보기" class="shrink-0 w-20 h-12 object-cover rounded-lg border border-gray-100" />
                            {:else}
                                <div class="shrink-0 w-10 h-10 rounded-lg bg-gray-100 flex items-center justify-center">
                                    <svg class="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"/>
                                    </svg>
                                </div>
                            {/if}
                            <span class="flex-1 text-sm text-gray-600 truncate min-w-0">{item.url}</span>
                            <button type="button" onclick={() => newUrls = newUrls.filter((_, j) => j !== i)}
                                class="shrink-0 w-7 h-7 rounded-full text-gray-400 hover:bg-red-50 hover:text-red-500 flex items-center justify-center transition-colors opacity-0 group-hover:opacity-100">
                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M6 18L18 6M6 6l12 12"/>
                                </svg>
                            </button>
                        </div>
                    {/each}
                </div>
            {/if}
        </div>

        {#if error}<p class="text-red-500 text-sm font-medium">{error}</p>{/if}

        <div class="flex gap-4 pt-2">
            <button type="submit" disabled={submitting}
                class="px-8 py-3 bg-primary-900 text-white font-bold rounded-full hover:bg-primary-800 transition-colors disabled:opacity-60 disabled:cursor-not-allowed">
                {submitting ? submitLabel : '저장하기'}
            </button>
            <a href={`/board/${data.post.id}`}
                class="px-8 py-3 bg-white text-gray-700 font-bold rounded-full border-2 border-gray-200 hover:border-gray-400 transition-colors">
                취소
            </a>
        </div>
    </form>
</div>
{/if}
