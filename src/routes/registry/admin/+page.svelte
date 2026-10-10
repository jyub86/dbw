<script lang="ts">
    import RegistryGate from '$lib/components/RegistryGate.svelte';
    import AdminPanel from '$lib/registry/AdminPanel.svelte';
</script>

<RegistryGate need="admin">
    {#snippet children()}
        <AdminPanel />
    {/snippet}
</RegistryGate>
