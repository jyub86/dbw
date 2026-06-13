import type { PageServerLoad } from './$types';
import { supabase } from '$lib/supabase';

const VIDEO_CATEGORY_IDS = [4, 5, 6, 9, 14]; // 설교, 찬양, 예배실황, 1401MEDIA, 수요 성경 아카데미
const VIDEO_ONLY_CATEGORY_IDS = [9]; // YouTube URL이 있는 게시물만 표시

function getYoutubeId(url: string): string | null {
	const match = url.match(/(?:v=|youtu\.be\/|embed\/|shorts\/)([^&?/]+)/);
	return match ? match[1] : null;
}

export const load: PageServerLoad = async () => {
	const [postsRes, categoriesRes] = await Promise.all([
		supabase
			.from('posts')
			.select('id, title, category_id, media_urls, created_at')
			.in('category_id', VIDEO_CATEGORY_IDS)
			.eq('active', true)
			.order('created_at', { ascending: false }),
		supabase
			.from('categories')
			.select('id, name')
			.in('id', VIDEO_CATEGORY_IDS)
			.order('order', { ascending: true }),
	]);

	const categories = categoriesRes.data ?? [];
	const categoryMap: Record<number, string> = {};
	for (const c of categories) {
		categoryMap[c.id] = c.name;
	}

	const allVideos = (postsRes.data ?? [])
		.filter((post) => {
			if (!VIDEO_ONLY_CATEGORY_IDS.includes(post.category_id)) return true;
			const firstUrl = post.media_urls?.[0] ?? '';
			return !!getYoutubeId(firstUrl);
		})
		.map((post) => {
			const youtubeUrl = post.media_urls?.[0] ?? '';
			const youtubeId = getYoutubeId(youtubeUrl);
			return {
				id: post.id,
				title: post.title,
				category_id: post.category_id,
				category: categoryMap[post.category_id] ?? '',
				date: new Date(post.created_at).toLocaleDateString('ko-KR', {
					year: 'numeric', month: '2-digit', day: '2-digit'
				}),
				thumbnail: youtubeId ? `https://img.youtube.com/vi/${youtubeId}/maxresdefault.jpg` : '',
				youtubeUrl,
			};
		});

	return { videos: allVideos, categories };
};
