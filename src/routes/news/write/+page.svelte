<script lang="ts">
    import { goto } from '$app/navigation';
    import { onMount } from 'svelte';
    import { supabaseBrowser } from '$lib/supabase-browser';

    let { data } = $props();

    let title = $state('');
    let content = $state('');
    let categoryId = $state<number>(data.categories[0]?.id ?? 2);
    let submitting = $state(false);
    let submitLabel = $state('등록하기');
    let error = $state('');
    let authChecked = $state(false);

    // 이미지 첨부
    type ImageItem = { file: File; previewUrl: string };
    let images = $state<ImageItem[]>([]);
    let fileInput = $state<HTMLInputElement | null>(null);
    let isDraggingImage = $state(false);

    // 외부 URL 첨부
    type UrlItem = { url: string; type: 'youtube' | 'image' | 'other' };
    let urlItems = $state<UrlItem[]>([]);
    let urlInput = $state('');
    let urlError = $state('');

    // PDF 첨부 (교회소식 전용)
    type PdfItem = { file: File; name: string };
    let pdfItems = $state<PdfItem[]>([]);
    let pdfInput = $state<HTMLInputElement | null>(null);
    let isDraggingPdf = $state(false);

    const MAX_WIDTH = 1920;
    const MAX_HEIGHT = 1080;
    const MAX_IMAGES = 10;
    const MAX_URLS = 10;
    const MAX_PDFS = 5;
    const MANAGER_LEVEL = 50;
    const PDF_ALLOWED_CATEGORY_IDS = [2, 12]; // 교회소식, 구역공과

    onMount(async () => {
        const { data: { session } } = await supabaseBrowser.auth.getSession();
        if (!session) { goto('/login'); return; }

        const { data: userInfo } = await supabaseBrowser
            .from('custom_users')
            .select('roles(level)')
            .eq('auth_id', session.user.id)
            .single();

        const level = (userInfo?.roles as { level: number } | null)?.level ?? 0;
        if (level < MANAGER_LEVEL) { goto('/news'); return; }

        authChecked = true;
    });

    // ── URL 유틸 ─────────────────────────────────────────────
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

    function detectUrlType(url: string): UrlItem['type'] {
        if (getYouTubeId(url)) return 'youtube';
        if (/\.(jpe?g|png|gif|webp|bmp|svg)(\?.*)?$/i.test(url)) return 'image';
        return 'other';
    }

    function addUrl() {
        urlError = '';
        const trimmed = urlInput.trim();
        if (!trimmed) return;
        try { new URL(trimmed); } catch {
            urlError = '올바른 URL을 입력해주세요.';
            return;
        }
        if (urlItems.some(u => u.url === trimmed)) { urlError = '이미 추가된 URL입니다.'; return; }
        if (urlItems.length >= MAX_URLS) { urlError = `URL은 최대 ${MAX_URLS}개까지 추가할 수 있습니다.`; return; }
        urlItems = [...urlItems, { url: trimmed, type: detectUrlType(trimmed) }];
        urlInput = '';
    }

    function removeUrl(index: number) { urlItems = urlItems.filter((_, i) => i !== index); }
    function handleUrlKeydown(e: KeyboardEvent) { if (e.key === 'Enter') { e.preventDefault(); addUrl(); } }

    // ── 이미지 리사이즈 ──────────────────────────────────────
    function resizeImage(file: File): Promise<Blob> {
        return new Promise((resolve) => {
            const img = new Image();
            const objectUrl = URL.createObjectURL(file);
            img.onload = () => {
                URL.revokeObjectURL(objectUrl);
                let { width, height } = img;
                if (width <= MAX_WIDTH && height <= MAX_HEIGHT) { resolve(file); return; }
                const ratio = Math.min(MAX_WIDTH / width, MAX_HEIGHT / height);
                width = Math.round(width * ratio);
                height = Math.round(height * ratio);
                const canvas = document.createElement('canvas');
                canvas.width = width; canvas.height = height;
                canvas.getContext('2d')!.drawImage(img, 0, 0, width, height);
                canvas.toBlob((blob) => resolve(blob!), 'image/jpeg', 0.92);
            };
            img.src = objectUrl;
        });
    }

    function addImageFiles(files: File[]) {
        for (const file of files.slice(0, MAX_IMAGES - images.length)) {
            if (!file.type.startsWith('image/')) continue;
            images = [...images, { file, previewUrl: URL.createObjectURL(file) }];
        }
    }

    function handleFileChange(e: Event) {
        const input = e.target as HTMLInputElement;
        addImageFiles(Array.from(input.files ?? []));
        input.value = '';
    }

    function handleImageDrop(e: DragEvent) {
        e.preventDefault();
        isDraggingImage = false;
        addImageFiles(Array.from(e.dataTransfer?.files ?? []));
    }

    function handleImageDragOver(e: DragEvent) {
        e.preventDefault();
        isDraggingImage = true;
    }

    function handleImageDragLeave(e: DragEvent) {
        if (!(e.currentTarget as Element).contains(e.relatedTarget as Node)) {
            isDraggingImage = false;
        }
    }

    function removeImage(index: number) {
        URL.revokeObjectURL(images[index].previewUrl);
        images = images.filter((_, i) => i !== index);
    }

    // ── PDF 첨부 ─────────────────────────────────────────────
    function addPdfFiles(files: File[]) {
        for (const file of files.slice(0, MAX_PDFS - pdfItems.length)) {
            if (file.type !== 'application/pdf') continue;
            pdfItems = [...pdfItems, { file, name: file.name }];
        }
    }

    function handlePdfChange(e: Event) {
        const input = e.target as HTMLInputElement;
        addPdfFiles(Array.from(input.files ?? []));
        input.value = '';
    }

    function handlePdfDrop(e: DragEvent) {
        e.preventDefault();
        isDraggingPdf = false;
        addPdfFiles(Array.from(e.dataTransfer?.files ?? []));
    }

    function handlePdfDragOver(e: DragEvent) {
        e.preventDefault();
        isDraggingPdf = true;
    }

    function handlePdfDragLeave(e: DragEvent) {
        if (!(e.currentTarget as Element).contains(e.relatedTarget as Node)) {
            isDraggingPdf = false;
        }
    }

    function removePdf(index: number) {
        pdfItems = pdfItems.filter((_, i) => i !== index);
    }

    function formatFileSize(bytes: number): string {
        if (bytes < 1024) return `${bytes} B`;
        if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
        return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    }

    // ── 등록 ────────────────────────────────────────────────
    async function handleSubmit(e: Event) {
        e.preventDefault();
        if (!title.trim()) { error = '제목을 입력해주세요.'; return; }

        submitting = true; error = '';

        const { data: { session } } = await supabaseBrowser.auth.getSession();
        if (!session) { goto('/login'); return; }

        submitLabel = '게시물 등록 중...';
        const { data: post, error: insertErr } = await supabaseBrowser
            .from('posts')
            .insert({ title: title.trim(), content: content.trim(), category_id: categoryId, user_id: session.user.id, active: true })
            .select('id').single();

        if (insertErr || !post) {
            error = '게시물 등록에 실패했습니다. 다시 시도해주세요.';
            submitting = false; submitLabel = '등록하기'; return;
        }

        const mediaUrls: string[] = [];

        if (images.length > 0) {
            for (let i = 0; i < images.length; i++) {
                submitLabel = `이미지 업로드 중... (${i + 1}/${images.length})`;
                const blob = await resizeImage(images[i].file);
                const path = `${session.user.id}/posts_${post.id}_${i + 1}.jpg`;
                const { error: uploadErr } = await supabaseBrowser.storage
                    .from('posts').upload(path, blob, { contentType: 'image/jpeg', upsert: true });
                if (uploadErr) continue;
                const { data: urlData } = supabaseBrowser.storage.from('posts').getPublicUrl(path);
                if (urlData?.publicUrl) mediaUrls.push(urlData.publicUrl);
            }
        }

        for (const item of urlItems) mediaUrls.push(item.url);

        // PDF 업로드 (교회소식 전용)
        const attachments: { name: string; url: string }[] = [];
        if (PDF_ALLOWED_CATEGORY_IDS.includes(categoryId) && pdfItems.length > 0) {
            for (let i = 0; i < pdfItems.length; i++) {
                submitLabel = `PDF 업로드 중... (${i + 1}/${pdfItems.length})`;
                const { file, name } = pdfItems[i];
                const path = `${session.user.id}/posts_${post.id}_attachment_${i + 1}.pdf`;
                const { error: uploadErr } = await supabaseBrowser.storage
                    .from('posts').upload(path, file, { contentType: 'application/pdf', upsert: true });
                if (uploadErr) continue;
                const { data: urlData } = supabaseBrowser.storage.from('posts').getPublicUrl(path);
                if (urlData?.publicUrl) attachments.push({ name, url: urlData.publicUrl });
            }
        }

        const updates: Record<string, unknown> = {};
        if (mediaUrls.length > 0) updates.media_urls = mediaUrls;
        if (attachments.length > 0) updates.attachments = attachments;
        if (Object.keys(updates).length > 0) {
            await supabaseBrowser.from('posts').update(updates).eq('id', post.id);
        }

        goto(`/news/${post.id}`);
    }
</script>

<svelte:head>
    <title>글쓰기 - 교회 소식 - 부평동부교회</title>
</svelte:head>

{#if authChecked}
<div class="w-full max-w-6xl mx-auto px-6 sm:px-8 lg:px-12 py-16">
    <a href="/news" class="inline-flex items-center gap-2 text-gray-500 hover:text-primary-600 font-medium mb-10 transition-colors">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/>
        </svg>
        교회 소식으로 돌아가기
    </a>

    <h1 class="text-3xl md:text-4xl font-black text-gray-900 mb-10">글쓰기</h1>

    <form onsubmit={handleSubmit} class="space-y-7">
        <!-- 분류 -->
        <div>
            <label for="category" class="block text-sm font-bold text-gray-700 mb-2">분류</label>
            <select id="category" bind:value={categoryId}
                class="w-full sm:w-48 px-4 py-3 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 transition-colors text-base font-medium bg-white">
                {#each data.categories as cat}
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

        <!-- 이미지 첨부 -->
        <div>
            <div class="flex items-center justify-between mb-3">
                <label class="text-sm font-bold text-gray-700">
                    이미지 첨부 <span class="text-gray-400 font-normal">({images.length}/{MAX_IMAGES})</span>
                </label>
                {#if images.length > 0 && images.length < MAX_IMAGES}
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

            <!-- 드롭존 -->
            <div
                role="region"
                aria-label="이미지 드롭존"
                ondrop={handleImageDrop}
                ondragover={handleImageDragOver}
                ondragleave={handleImageDragLeave}
                class="relative rounded-2xl transition-all duration-150 {isDraggingImage ? 'ring-2 ring-primary-400' : ''}"
            >
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

                {#if images.length === 0}
                    <button type="button" onclick={() => fileInput?.click()}
                        class="w-full border-2 border-dashed rounded-2xl py-10 flex flex-col items-center gap-3 transition-colors {isDraggingImage ? 'border-primary-400 text-primary-500 bg-primary-50' : 'border-gray-200 text-gray-400 hover:border-primary-300 hover:text-primary-500'}">
                        <svg class="w-9 h-9" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                        </svg>
                        <span class="text-sm font-medium">클릭하거나 드래그 앤 드롭으로 이미지 첨부</span>
                        <span class="text-xs">최대 {MAX_IMAGES}장 · 1920×1080 초과 시 자동 리사이즈</span>
                    </button>
                {:else}
                    <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 gap-3">
                        {#each images as img, i}
                            <div class="relative group aspect-square rounded-xl overflow-hidden border-2 border-gray-100 bg-gray-50">
                                <img src={img.previewUrl} alt={`첨부 이미지 ${i + 1}`} class="w-full h-full object-cover" />
                                <button type="button" onclick={() => removeImage(i)}
                                    class="absolute top-1.5 right-1.5 w-6 h-6 rounded-full bg-black/60 text-white flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity hover:bg-red-500">
                                    <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M6 18L18 6M6 6l12 12"/>
                                    </svg>
                                </button>
                                <div class="absolute bottom-1.5 left-1.5 text-[10px] font-bold text-white bg-black/40 px-1.5 py-0.5 rounded">{i + 1}</div>
                            </div>
                        {/each}
                        {#if images.length < MAX_IMAGES}
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

        <!-- 외부 URL 첨부 -->
        <div>
            <label class="block text-sm font-bold text-gray-700 mb-3">
                URL 첨부 <span class="text-gray-400 font-normal">— 이미지 또는 YouTube 영상</span>
            </label>
            <div class="flex gap-2 mb-3">
                <input type="url" bind:value={urlInput} onkeydown={handleUrlKeydown} placeholder="https://..."
                    class="flex-1 px-4 py-3 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 transition-colors text-base" />
                <button type="button" onclick={addUrl}
                    class="shrink-0 px-5 py-3 bg-gray-900 text-white font-bold rounded-xl hover:bg-gray-700 transition-colors text-sm">
                    추가
                </button>
            </div>
            {#if urlError}<p class="text-red-500 text-xs font-medium mb-3">{urlError}</p>{/if}

            {#if urlItems.length > 0}
                <div class="space-y-2">
                    {#each urlItems as item, i}
                        <div class="flex items-center gap-3 p-3 bg-gray-50 rounded-xl border border-gray-100 group">
                            {#if item.type === 'youtube'}
                                <div class="shrink-0 w-10 h-10 rounded-lg bg-red-100 flex items-center justify-center">
                                    <svg class="w-5 h-5 text-red-600" viewBox="0 0 24 24" fill="currentColor">
                                        <path d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z"/>
                                    </svg>
                                </div>
                                <img src={`https://img.youtube.com/vi/${getYouTubeId(item.url)}/mqdefault.jpg`} alt="YouTube 썸네일"
                                    class="shrink-0 w-20 h-12 object-cover rounded-lg border border-gray-100" />
                            {:else if item.type === 'image'}
                                <div class="shrink-0 w-10 h-10 rounded-lg bg-blue-50 flex items-center justify-center">
                                    <svg class="w-5 h-5 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                                    </svg>
                                </div>
                                <img src={item.url} alt="이미지 미리보기" class="shrink-0 w-20 h-12 object-cover rounded-lg border border-gray-100" />
                            {:else}
                                <div class="shrink-0 w-10 h-10 rounded-lg bg-gray-100 flex items-center justify-center">
                                    <svg class="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"/>
                                    </svg>
                                </div>
                            {/if}
                            <span class="flex-1 text-sm text-gray-600 truncate min-w-0">{item.url}</span>
                            <button type="button" onclick={() => removeUrl(i)}
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

        <!-- PDF 첨부 (교회소식 카테고리 전용) -->
        {#if PDF_ALLOWED_CATEGORY_IDS.includes(categoryId)}
            <div>
                <div class="flex items-center justify-between mb-3">
                    <label class="text-sm font-bold text-gray-700">
                        PDF 첨부 <span class="text-gray-400 font-normal">({pdfItems.length}/{MAX_PDFS}) · 교회소식 전용</span>
                    </label>
                    {#if pdfItems.length > 0 && pdfItems.length < MAX_PDFS}
                        <button type="button" onclick={() => pdfInput?.click()}
                            class="inline-flex items-center gap-1.5 px-4 py-2 rounded-full text-sm font-bold border-2 border-gray-200 text-gray-600 hover:border-primary-400 hover:text-primary-700 transition-colors">
                            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
                            </svg>
                            PDF 추가
                        </button>
                    {/if}
                </div>

                <input type="file" accept="application/pdf" multiple bind:this={pdfInput} onchange={handlePdfChange} class="hidden" />

                <!-- PDF 드롭존 -->
                <div
                    role="region"
                    aria-label="PDF 드롭존"
                    ondrop={handlePdfDrop}
                    ondragover={handlePdfDragOver}
                    ondragleave={handlePdfDragLeave}
                    class="relative rounded-2xl transition-all duration-150 {isDraggingPdf ? 'ring-2 ring-red-400' : ''}"
                >
                    {#if isDraggingPdf}
                        <div class="absolute inset-0 rounded-2xl border-2 border-dashed border-red-400 bg-red-50/90 flex items-center justify-center z-10 pointer-events-none">
                            <div class="flex flex-col items-center gap-2 text-red-500">
                                <svg class="w-10 h-10" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z"/>
                                </svg>
                                <span class="font-bold text-base">PDF를 여기에 놓으세요</span>
                            </div>
                        </div>
                    {/if}

                    {#if pdfItems.length === 0}
                        <button type="button" onclick={() => pdfInput?.click()}
                            class="w-full border-2 border-dashed rounded-2xl py-10 flex flex-col items-center gap-3 transition-colors {isDraggingPdf ? 'border-red-400 text-red-400 bg-red-50' : 'border-red-100 text-gray-400 hover:border-red-300 hover:text-red-400'}">
                            <svg class="w-9 h-9" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z"/>
                            </svg>
                            <span class="text-sm font-medium">클릭하거나 드래그 앤 드롭으로 PDF 첨부</span>
                            <span class="text-xs">최대 {MAX_PDFS}개</span>
                        </button>
                    {:else}
                        <div class="space-y-2">
                            {#each pdfItems as pdf, i}
                                <div class="flex items-center gap-3 p-3 bg-red-50 rounded-xl border border-red-100 group">
                                    <div class="shrink-0 w-10 h-10 rounded-lg bg-red-100 flex items-center justify-center">
                                        <svg class="w-5 h-5 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z"/>
                                        </svg>
                                    </div>
                                    <div class="flex-1 min-w-0">
                                        <p class="text-sm font-medium text-gray-800 truncate">{pdf.name}</p>
                                        <p class="text-xs text-gray-400">{formatFileSize(pdf.file.size)}</p>
                                    </div>
                                    <button type="button" onclick={() => removePdf(i)}
                                        class="shrink-0 w-7 h-7 rounded-full text-gray-400 hover:bg-red-200 hover:text-red-600 flex items-center justify-center transition-colors opacity-0 group-hover:opacity-100">
                                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M6 18L18 6M6 6l12 12"/>
                                        </svg>
                                    </button>
                                </div>
                            {/each}
                            {#if pdfItems.length < MAX_PDFS}
                                <button type="button" onclick={() => pdfInput?.click()}
                                    class="w-full flex items-center justify-center gap-2 py-2.5 rounded-xl border-2 border-dashed border-red-100 text-red-300 hover:border-red-300 hover:text-red-400 transition-colors text-sm font-medium">
                                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
                                    </svg>
                                    PDF 추가
                                </button>
                            {/if}
                        </div>
                    {/if}
                </div>
            </div>
        {/if}

        {#if error}<p class="text-red-500 text-sm font-medium">{error}</p>{/if}

        <div class="flex gap-4 pt-2">
            <button type="submit" disabled={submitting}
                class="px-8 py-3 bg-primary-900 text-white font-bold rounded-full hover:bg-primary-800 transition-colors disabled:opacity-60 disabled:cursor-not-allowed">
                {submitting ? submitLabel : '등록하기'}
            </button>
            <a href="/news"
                class="px-8 py-3 bg-white text-gray-700 font-bold rounded-full border-2 border-gray-200 hover:border-gray-400 transition-colors">
                취소
            </a>
        </div>
    </form>
</div>
{/if}
