<script lang="ts">
    import RegistryGate from '$lib/components/RegistryGate.svelte';
    import Candidates from '$lib/registry/Candidates.svelte';
</script>

<RegistryGate need="view">
    {#snippet children(me)}
        <Candidates {me} />
    {/snippet}
</RegistryGate>
