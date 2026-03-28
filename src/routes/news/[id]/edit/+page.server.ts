import type { PageServerLoad } from './$types';
import { supabase } from '$lib/supabase';
import { error } from '@sveltejs/kit';

const NEWS_CATEGORY_IDS = [2, 3, 10, 12, 13];

export const load: PageServerLoad = async ({ params }) => {
	const [postRes, categoriesRes] = await Promise.all([
		supabase
			.from('posts')
			.select('id, title, content, media_urls, attachments, category_id, user_id')
			.eq('id', params.id)
			.eq('active', true)
			.single(),
		supabase
			.from('categories')
			.select('id, name')
			.in('id', NEWS_CATEGORY_IDS)
			.order('order', { ascending: true }),
	]);

	if (postRes.error || !postRes.data) throw error(404, '게시물을 찾을 수 없습니다.');

	return {
		post: {
			id: postRes.data.id,
			title: postRes.data.title,
			content: postRes.data.content ?? '',
			media_urls: (postRes.data.media_urls as string[]) ?? [],
			attachments: (postRes.data.attachments as { name: string; url: string }[]) ?? [],
			category_id: postRes.data.category_id,
			user_id: postRes.data.user_id as string,
		},
		categories: categoriesRes.data ?? [],
	};
};
