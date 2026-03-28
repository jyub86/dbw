import type { PageServerLoad } from './$types';
import { supabase } from '$lib/supabase';

const BOARD_CATEGORY_IDS = [7, 9];

export const load: PageServerLoad = async () => {
	const { data: categories } = await supabase
		.from('categories')
		.select('id, name')
		.in('id', BOARD_CATEGORY_IDS)
		.order('order', { ascending: true });

	return { categories: categories ?? [] };
};
