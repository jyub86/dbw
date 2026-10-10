<script lang="ts">
    import RegistryGate from '$lib/components/RegistryGate.svelte';
    import PeopleList from '$lib/registry/PeopleList.svelte';
</script>

<RegistryGate need="view">
    {#snippet children(me)}
        <PeopleList {me} />
    {/snippet}
</RegistryGate>
