import type { PageServerLoad } from './$types';
import { supabase } from '$lib/supabase';

const ALL_CATEGORY_IDS = [2, 3, 10, 12, 13];
const PAGE_SIZE = 20;

// 화면에 보여줄 카테고리 필터 버튼 정의
const FILTER_CATEGORIES = [
	{ label: '교회소식', ids: [2] },
	{ label: '주보', ids: [3] },
	{ label: '교우동정', ids: [10] },
	{ label: '구역공과', ids: [12] },
	{ label: '선교소식', ids: [13] },
];

export const load: PageServerLoad = async ({ url }) => {
	const page = Math.max(1, Number(url.searchParams.get('page') ?? '1'));
	const categoryParam = url.searchParams.get('category'); // 필터 label 값 (e.g. "교회소식")
	const search = url.searchParams.get('search') ?? '';

	// 선택된 필터에 해당하는 카테고리 ID 목록
	const selectedFilter = categoryParam
		? FILTER_CATEGORIES.find((f) => f.label === categoryParam)
		: null;
	const categoryIds = selectedFilter ? selectedFilter.ids : ALL_CATEGORY_IDS;

	let query = supabase
		.from('posts')
		.select('id, title, category_id, created_at', { count: 'exact' })
		.in('category_id', categoryIds)
		.eq('active', true)
		.order('created_at', { ascending: false })
		.range((page - 1) * PAGE_SIZE, page * PAGE_SIZE - 1);

	if (search) {
		query = query.ilike('title', `%${search}%`);
	}

	const { data, count } = await query;

	const totalCount = count ?? 0;
	const totalPages = Math.ceil(totalCount / PAGE_SIZE);

	// 카테고리 ID → 표시 label 매핑
	const categoryLabelMap: Record<number, string> = {};
	for (const f of FILTER_CATEGORIES) {
		for (const id of f.ids) {
			categoryLabelMap[id] = f.label;
		}
	}

	const news = (data ?? []).map((post) => ({
		id: post.id,
		title: post.title,
		category_id: post.category_id,
		category: categoryLabelMap[post.category_id] ?? '기타',
		date: new Date(post.created_at).toLocaleDateString('ko-KR', {
			year: 'numeric',
			month: '2-digit',
			day: '2-digit'
		}),
		isNew: new Date(post.created_at) > new Date(Date.now() - 7 * 24 * 60 * 60 * 1000)
	}));

	return {
		news,
		filterCategories: FILTER_CATEGORIES.map((f) => f.label),
		page,
		totalPages,
		totalCount,
		search,
		categoryParam: categoryParam ?? null
	};
};
