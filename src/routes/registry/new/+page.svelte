<script lang="ts">
    import RegistryGate from '$lib/components/RegistryGate.svelte';
    import NewcomerForm from '$lib/registry/NewcomerForm.svelte';
</script>

<RegistryGate need="edit">
    {#snippet children(me)}
        <NewcomerForm {me} />
    {/snippet}
</RegistryGate>
