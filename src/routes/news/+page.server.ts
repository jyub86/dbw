import type { PageServerLoad } from './$types';
import { supabase } from '$lib/supabase';

const NEWS_CATEGORY_IDS = [2, 3]; // 교회소식, 주보

export const load: PageServerLoad = async () => {
	const [postsRes, categoriesRes] = await Promise.all([
		supabase
			.from('posts')
			.select('id, title, category_id, created_at')
			.in('category_id', NEWS_CATEGORY_IDS)
			.eq('active', true)
			.order('created_at', { ascending: false }),
		supabase
			.from('categories')
			.select('id, name')
			.in('id', NEWS_CATEGORY_IDS)
			.order('order', { ascending: true }),
	]);

	const categoryMap: Record<number, string> = {};
	for (const c of categoriesRes.data ?? []) {
		categoryMap[c.id] = c.name;
	}

	const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);

	const news = (postsRes.data ?? []).map((post) => ({
		id: post.id,
		title: post.title,
		category_id: post.category_id,
		category: categoryMap[post.category_id] ?? '',
		date: new Date(post.created_at).toLocaleDateString('ko-KR', {
			year: 'numeric', month: '2-digit', day: '2-digit'
		}),
		isNew: new Date(post.created_at) > sevenDaysAgo,
	}));

	return { news, categories: categoriesRes.data ?? [] };
};
