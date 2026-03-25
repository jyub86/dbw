import type { PageServerLoad } from './$types';
import { supabase } from '$lib/supabase';

const BOARD_CATEGORY_IDS = [7, 9]; // 게시판, 1401 MEDIA
const PAGE_SIZE = 20;

export const load: PageServerLoad = async ({ url }) => {
	const page = Math.max(1, Number(url.searchParams.get('page') ?? '1'));
	const categoryId = url.searchParams.get('category');
	const search = url.searchParams.get('search') ?? '';

	const categoryIds = categoryId ? [Number(categoryId)] : BOARD_CATEGORY_IDS;

	let query = supabase
		.from('posts')
		.select(`
			id, title, created_at, category_id,
			custom_users!posts_user_id_fkey(name)
		`, { count: 'exact' })
		.in('category_id', categoryIds)
		.eq('active', true)
		.order('created_at', { ascending: false })
		.range((page - 1) * PAGE_SIZE, page * PAGE_SIZE - 1);

	if (search) {
		query = query.ilike('title', `%${search}%`);
	}

	const [postsRes, categoriesRes] = await Promise.all([
		query,
		supabase
			.from('categories')
			.select('id, name')
			.in('id', BOARD_CATEGORY_IDS)
			.order('order', { ascending: true }),
	]);

	const totalCount = postsRes.count ?? 0;
	const totalPages = Math.ceil(totalCount / PAGE_SIZE);

	const posts = (postsRes.data ?? []).map((post) => ({
		id: post.id,
		title: post.title,
		category_id: post.category_id,
		author: (post.custom_users as { name: string } | null)?.name ?? '알 수 없음',
		date: new Date(post.created_at).toLocaleDateString('ko-KR', {
			year: 'numeric', month: '2-digit', day: '2-digit'
		}),
	}));

	return {
		posts,
		categories: categoriesRes.data ?? [],
		page,
		totalPages,
		totalCount,
		search,
		categoryId: categoryId ? Number(categoryId) : null,
	};
};
