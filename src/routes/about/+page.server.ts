import type { PageServerLoad } from './$types';
import { supabase } from '$lib/supabase';

export const load: PageServerLoad = async () => {
	const { data, error } = await supabase
		.from('church_history')
		.select('event_date, description, decade')
		.order('sort_order', { ascending: true });

	if (error) {
		console.error('Failed to load church history:', error);
		return { historyData: [] };
	}

	// Group by decade
	const grouped = new Map<string, { date: string; desc: string }[]>();
	for (const row of data ?? []) {
		const dateStr = row.event_date.replace(/-/g, '.').slice(0, 10);
		if (!grouped.has(row.decade)) grouped.set(row.decade, []);
		grouped.get(row.decade)!.push({ date: dateStr, desc: row.description });
	}

	const historyData = Array.from(grouped.entries()).map(([decade, events]) => ({
		decade,
		events
	}));

	return { historyData };
};
