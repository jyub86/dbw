<script lang="ts">
    import RegistryGate from '$lib/components/RegistryGate.svelte';
    import ImportPanel from '$lib/registry/ImportPanel.svelte';
</script>

<RegistryGate need="edit">
    {#snippet children(me)}
        <ImportPanel {me} />
    {/snippet}
</RegistryGate>
