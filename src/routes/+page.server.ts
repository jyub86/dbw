import type { PageServerLoad } from './$types';
import { supabase } from '$lib/supabase';

const VIDEO_CATEGORY_IDS = [4, 5, 6, 14]; // 설교, 찬양, 예배실황, 수요 성경 아카데미

// 메인 하단 최근 글 네 칸. 1401 MEDIA 만 일반 게시판(/board) 쪽 글이다
const RECENT_SECTIONS = [
	{ title: '교회 소식', categoryId: 2, base: '/news', more: '/news?category=교회소식' },
	{ title: '교육 자료', categoryId: 12, base: '/news', more: '/news?category=교육자료' },
	{ title: '선교 소식', categoryId: 13, base: '/news', more: '/news?category=선교소식' },
	{ title: '1401 MEDIA', categoryId: 9, base: '/board', more: '/board?category=9' },
];
const RECENT_LIMIT = 5;

// 올해 글은 월·일만, 지난해 글은 연도까지 (글이 뜸한 칸에서 오래된 글이 최근 글처럼 보이지 않게)
function shortDate(iso: string): string {
	const d = new Date(iso);
	const year = (x: Date) => x.toLocaleDateString('ko-KR', { timeZone: 'Asia/Seoul', year: 'numeric' });
	return d.toLocaleDateString('ko-KR', {
		timeZone: 'Asia/Seoul',
		...(year(d) === year(new Date()) ? {} : { year: 'numeric' }),
		month: '2-digit',
		day: '2-digit',
	});
}

function getYoutubeId(url: string): string | null {
	const match = url.match(/(?:v=|youtu\.be\/)([^&?/]+)/);
	return match ? match[1] : null;
}

export const load: PageServerLoad = async () => {
	const [bannersRes, postsRes, categoriesRes, recentRes] = await Promise.all([
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
		Promise.all(
			RECENT_SECTIONS.map((s) =>
				supabase
					.from('posts')
					.select('id, title, created_at')
					.eq('category_id', s.categoryId)
					.eq('active', true)
					.order('created_at', { ascending: false })
					.limit(RECENT_LIMIT)
			)
		),
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

	const recent = RECENT_SECTIONS.map((s, i) => ({
		title: s.title,
		more: s.more,
		posts: (recentRes[i].data ?? []).map((post) => ({
			id: post.id,
			title: post.title,
			href: `${s.base}/${post.id}`,
			date: shortDate(post.created_at),
		})),
	}));

	return {
		banners: bannersRes.data ?? [],
		videos,
		recent,
	};
};
