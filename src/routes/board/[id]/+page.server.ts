import type { PageServerLoad } from './$types';
import { supabase } from '$lib/supabase';
import { error } from '@sveltejs/kit';

export const load: PageServerLoad = async ({ params }) => {
	const { data, error: err } = await supabase
		.from('posts')
		.select(`
			id, title, content, media_urls, created_at, category_id,
			categories(name),
			custom_users!posts_user_id_fkey(name, profile_picture)
		`)
		.eq('id', params.id)
		.eq('active', true)
		.single();

	if (err || !data) throw error(404, '게시물을 찾을 수 없습니다.');

	return {
		post: {
			id: data.id,
			title: data.title,
			content: data.content,
			media_urls: data.media_urls ?? [],
			category: (data.categories as { name: string })?.name ?? '',
			author: (data.custom_users as { name: string; profile_picture: string | null } | null)?.name ?? '알 수 없음',
			authorProfile: (data.custom_users as { name: string; profile_picture: string | null } | null)?.profile_picture ?? null,
			date: new Date(data.created_at).toLocaleDateString('ko-KR', {
				year: 'numeric', month: '2-digit', day: '2-digit'
			}),
		}
	};
};
