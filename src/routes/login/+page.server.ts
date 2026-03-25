import type { PageServerLoad } from './$types';
import { supabase } from '$lib/supabase';

export const load: PageServerLoad = async () => {
	const { data, error } = await supabase
		.from('login_settings')
		.select('login, value');

	if (error) {
		console.error('Failed to load login settings:', error);
		return { loginSettings: {} };
	}

	const loginSettings: Record<string, boolean> = {};
	for (const row of data ?? []) {
		loginSettings[row.login] = row.value;
	}

	return { loginSettings };
};
