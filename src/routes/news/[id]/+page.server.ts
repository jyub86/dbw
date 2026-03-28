import type { PageServerLoad } from './$types';
import { supabase } from '$lib/supabase';
import { error } from '@sveltejs/kit';

export const load: PageServerLoad = async ({ params }) => {
	const { data, error: err } = await supabase
		.from('posts')
		.select('id, title, content, media_urls, attachments, created_at, category_id, categories(name)')
		.eq('id', params.id)
		.eq('active', true)
		.single();

	if (err || !data) throw error(404, '게시물을 찾을 수 없습니다.');

	return {
		post: {
			id: data.id,
			title: data.title,
			content: data.content,
			isHtml: typeof data.content === 'string' && data.content.trimStart().startsWith('<'),
			media_urls: (data.media_urls as string[]) ?? [],
			attachments: (data.attachments as { name: string; url: string }[]) ?? [],
			category: (data.categories as { name: string })?.name ?? '',
			date: new Date(data.created_at).toLocaleDateString('ko-KR', {
				year: 'numeric',
				month: '2-digit',
				day: '2-digit'
			})
		}
	};
};
