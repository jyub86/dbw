import type { PageServerLoad } from './$types';
import { supabase } from '$lib/supabase';

const NEWS_CATEGORY_IDS = [2, 3, 10, 12, 13];

export const load: PageServerLoad = async () => {
	const { data: categories } = await supabase
		.from('categories')
		.select('id, name')
		.in('id', NEWS_CATEGORY_IDS)
		.order('order', { ascending: true });

	return { categories: categories ?? [] };
};
