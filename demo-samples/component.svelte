<script lang="ts">
  // Svelte Component with TypeScript
  import { onMount, createEventDispatcher } from 'svelte';
  import { fade, slide } from 'svelte/transition';
  import type { User } from './types';
  
  // Component Props
  export let user: User;
  export let editable: boolean = false;
  export let theme: 'light' | 'dark' = 'light';
  
  // Local State
  let isEditing = false;
  let formData = { ...user };
  let errors: Record<string, string> = {};
  
  // Event Dispatcher
  const dispatch = createEventDispatcher();
  
  // Lifecycle
  onMount(() => {
    console.log('UserCard component mounted');
    return () => {
      console.log('UserCard component unmounted');
    };
  });
  
  // Methods
  function handleEdit() {
    isEditing = true;
    formData = { ...user };
  }
  
  function handleSave() {
    if (validateForm()) {
      dispatch('save', formData);
      user = { ...formData };
      isEditing = false;
    }
  }
  
  function handleCancel() {
    isEditing = false;
    formData = { ...user };
    errors = {};
  }
  
  function validateForm(): boolean {
    errors = {};
    
    if (!formData.name || formData.name.length < 2) {
      errors.name = 'Name must be at least 2 characters';
    }
    
    if (!formData.email || !formData.email.includes('@')) {
      errors.email = 'Please enter a valid email';
    }
    
    return Object.keys(errors).length === 0;
  }
  
  // Reactive Statements
  $: fullName = formData.name || 'Unknown User';
  $: initials = fullName.split(' ').map(n => n[0]).join('').toUpperCase();
</script>

<style>
  /* Component Styles */
  .user-card {
    --card-bg: white;
    --card-border: #e0e0e0;
    --card-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
    --text-primary: #333;
    --text-secondary: #666;
    
    background: var(--card-bg);
    border: 1px solid var(--card-border);
    border-radius: 12px;
    padding: 1.5rem;
    box-shadow: var(--card-shadow);
    transition: all 0.3s ease;
  }
  
  .user-card:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.15);
  }
  
  .user-card.dark {
    --card-bg: #2a2a2a;
    --card-border: #444;
    --text-primary: #f0f0f0;
    --text-secondary: #aaa;
  }
  
  .avatar {
    width: 64px;
    height: 64px;
    border-radius: 50%;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    display: flex;
    align-items: center;
    justify-content: center;
    color: white;
    font-weight: bold;
    font-size: 1.5rem;
    margin-bottom: 1rem;
  }
  
  .user-name {
    font-size: 1.5rem;
    font-weight: 600;
    color: var(--text-primary);
    margin-bottom: 0.5rem;
  }
  
  .user-email {
    color: var(--text-secondary);
    margin-bottom: 1rem;
  }
  
  .button-group {
    display: flex;
    gap: 0.5rem;
    margin-top: 1rem;
  }
  
  button {
    padding: 0.5rem 1rem;
    border: none;
    border-radius: 6px;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.2s ease;
  }
  
  .btn-primary {
    background: #007bff;
    color: white;
  }
  
  .btn-primary:hover {
    background: #0056b3;
  }
  
  .btn-secondary {
    background: #6c757d;
    color: white;
  }
  
  .btn-secondary:hover {
    background: #545b62;
  }
  
  input {
    width: 100%;
    padding: 0.5rem;
    border: 1px solid var(--card-border);
    border-radius: 4px;
    margin-bottom: 0.5rem;
    font-size: 1rem;
  }
  
  .error {
    color: #dc3545;
    font-size: 0.875rem;
    margin-top: 0.25rem;
  }
  
  @media (max-width: 768px) {
    .user-card {
      padding: 1rem;
    }
    
    .user-name {
      font-size: 1.25rem;
    }
  }
</style>

<!-- Template -->
<div class="user-card {theme}" transition:fade={{ duration: 200 }}>
  <div class="avatar">{initials}</div>
  
  {#if isEditing}
    <div transition:slide={{ duration: 200 }}>
      <input 
        type="text" 
        bind:value={formData.name} 
        placeholder="Name"
        class:error={errors.name}
      />
      {#if errors.name}
        <p class="error">{errors.name}</p>
      {/if}
      
      <input 
        type="email" 
        bind:value={formData.email} 
        placeholder="Email"
        class:error={errors.email}
      />
      {#if errors.email}
        <p class="error">{errors.email}</p>
      {/if}
      
      <div class="button-group">
        <button class="btn-primary" on:click={handleSave}>Save</button>
        <button class="btn-secondary" on:click={handleCancel}>Cancel</button>
      </div>
    </div>
  {:else}
    <h2 class="user-name">{user.name}</h2>
    <p class="user-email">{user.email}</p>
    
    {#if editable}
      <div class="button-group">
        <button class="btn-primary" on:click={handleEdit}>Edit Profile</button>
      </div>
    {/if}
  {/if}
</div>