import type { PageServerLoad } from './$types';
import { supabase } from '$lib/supabase';

const VIDEO_CATEGORY_IDS = [4, 5, 6]; // 설교, 찬양, 예배실황

function getYoutubeId(url: string): string | null {
	const match = url.match(/(?:v=|youtu\.be\/)([^&?/]+)/);
	return match ? match[1] : null;
}

export const load: PageServerLoad = async () => {
	const [bannersRes, postsRes, categoriesRes, newsRes, boardRes] = await Promise.all([
		supabase
			.from('banners')
			.select('id, title, image_url, link')
			.eq('active', true)
			.order('created_at', { ascending: true }),
		supabase
			.from('posts')
			.select('id, title, category_id, media_urls, created_at')
			.in('category_id', VIDEO_CATEGORY_IDS)
			.eq('active', true)
			.order('created_at', { ascending: false })
			.limit(3),
		supabase
			.from('categories')
			.select('id, name')
			.in('id', VIDEO_CATEGORY_IDS),
		supabase
			.from('posts')
			.select('id, title, category_id, created_at, categories(name)')
			.in('category_id', [2, 3])
			.eq('active', true)
			.order('created_at', { ascending: false })
			.limit(5),
		supabase
			.from('posts')
			.select('id, title, created_at, custom_users!posts_user_id_fkey(name)')
			.in('category_id', [7, 9])
			.eq('active', true)
			.order('created_at', { ascending: false })
			.limit(5),
	]);

	const categoryMap: Record<number, string> = {};
	for (const c of categoriesRes.data ?? []) {
		categoryMap[c.id] = c.name;
	}

	const videos = (postsRes.data ?? []).map((post) => {
		const url = post.media_urls?.[0] ?? '';
		const youtubeId = getYoutubeId(url);
		return {
			id: post.id,
			title: post.title,
			category: categoryMap[post.category_id] ?? '',
			date: new Date(post.created_at).toLocaleDateString('ko-KR', { year: 'numeric', month: '2-digit', day: '2-digit' }).replace(/\. /g, '. '),
			thumbnail: youtubeId ? `https://img.youtube.com/vi/${youtubeId}/hqdefault.jpg` : '',
			youtubeUrl: url,
		};
	});

	const latestNews = (newsRes.data ?? []).map((post) => ({
		id: post.id,
		title: post.title,
		category: (post.categories as unknown as { name: string })?.name ?? '',
		date: new Date(post.created_at).toLocaleDateString('ko-KR', { month: '2-digit', day: '2-digit' }),
	}));

	const latestBoard = (boardRes.data ?? []).map((post) => ({
		id: post.id,
		title: post.title,
		author: (post.custom_users as unknown as { name: string } | null)?.name ?? '알 수 없음',
		date: new Date(post.created_at).toLocaleDateString('ko-KR', { month: '2-digit', day: '2-digit' }),
	}));

	return {
		banners: bannersRes.data ?? [],
		videos,
		latestNews,
		latestBoard,
	};
};
