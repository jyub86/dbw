<script lang="ts">
    import { page } from '$app/stores';
    import RegistryGate from '$lib/components/RegistryGate.svelte';
    import PersonCard from '$lib/registry/PersonCard.svelte';

    const personId = $derived($page.params.id ?? '');
</script>

<RegistryGate need="view">
    {#snippet children(me)}
        {#key personId}
            <PersonCard {me} {personId} />
        {/key}
    {/snippet}
</RegistryGate>
