// Embedded code samples for demonstration
const std = @import("std");

pub const TypeScriptSample = 
    \\// TypeScript User Management System
    \\import { Database } from './database';
    \\
    \\interface User {
    \\    id: number;
    \\    name: string;
    \\    email: string;
    \\    createdAt: Date;
    \\}
    \\
    \\type UserRole = 'admin' | 'user' | 'guest';
    \\
    \\class UserService {
    \\    private db: Database;
    \\    
    \\    constructor(database: Database) {
    \\        this.db = database;
    \\    }
    \\    
    \\    async getUser(id: number): Promise<User> {
    \\        return await this.db.findOne('users', { id });
    \\    }
    \\    
    \\    async createUser(data: Partial<User>): Promise<User> {
    \\        const user = {
    \\            ...data,
    \\            createdAt: new Date()
    \\        };
    \\        return await this.db.insert('users', user);
    \\    }
    \\}
    \\
    \\export { UserService, User, UserRole };
;

pub const CssSample = 
    \\/* Modern CSS with Variables and Grid */
    \\@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;600&display=swap');
    \\
    \\:root {
    \\    --primary-color: #007bff;
    \\    --secondary-color: #6c757d;
    \\    --background: #ffffff;
    \\    --text-color: #333333;
    \\    --border-radius: 8px;
    \\    --spacing-unit: 1rem;
    \\}
    \\
    \\.container {
    \\    display: grid;
    \\    grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
    \\    gap: var(--spacing-unit);
    \\    padding: calc(var(--spacing-unit) * 2);
    \\}
    \\
    \\.card {
    \\    background: var(--background);
    \\    border-radius: var(--border-radius);
    \\    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
    \\    padding: var(--spacing-unit);
    \\    transition: transform 0.3s ease;
    \\}
    \\
    \\.card:hover {
    \\    transform: translateY(-4px);
    \\    box-shadow: 0 4px 8px rgba(0, 0, 0, 0.15);
    \\}
    \\
    \\@media (max-width: 768px) {
    \\    .container {
    \\        grid-template-columns: 1fr;
    \\    }
    \\}
;

pub const HtmlSample = 
    \\<!DOCTYPE html>
    \\<html lang="en">
    \\<head>
    \\    <meta charset="UTF-8">
    \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    \\    <title>Demo Application</title>
    \\    <link rel="stylesheet" href="styles.css">
    \\</head>
    \\<body>
    \\    <header class="header">
    \\        <nav class="nav">
    \\            <a href="#home" class="nav-link">Home</a>
    \\            <a href="#features" class="nav-link">Features</a>
    \\            <a href="#about" class="nav-link">About</a>
    \\        </nav>
    \\    </header>
    \\    
    \\    <main class="main-content">
    \\        <section id="hero" class="hero">
    \\            <h1>Welcome to Our Demo</h1>
    \\            <p>Experience the power of modern web development</p>
    \\            <button class="btn btn-primary">Get Started</button>
    \\        </section>
    \\        
    \\        <section id="features" class="features">
    \\            <div class="feature-card">
    \\                <h3>Fast Performance</h3>
    \\                <p>Optimized for speed and efficiency</p>
    \\            </div>
    \\        </section>
    \\    </main>
    \\    
    \\    <script src="app.js"></script>
    \\</body>
    \\</html>
;

pub const JsonSample = 
    \\{
    \\  "name": "zz-demo",
    \\  "version": "1.0.0",
    \\  "description": "Terminal demo for zz CLI utilities",
    \\  "author": {
    \\    "name": "Developer",
    \\    "email": "dev@example.com"
    \\  },
    \\  "config": {
    \\    "apiUrl": "https://api.example.com",
    \\    "timeout": 5000,
    \\    "retries": 3,
    \\    "features": {
    \\      "darkMode": true,
    \\      "notifications": false,
    \\      "analytics": true
    \\    }
    \\  },
    \\  "dependencies": {
    \\    "typescript": "^5.0.0",
    \\    "svelte": "^4.0.0"
    \\  }
    \\}
;

pub const SvelteSample = 
    \\<script lang="ts">
    \\  import { onMount, createEventDispatcher } from 'svelte';
    \\  import type { User } from './types';
    \\  
    \\  export let user: User;
    \\  export let editable = false;
    \\  
    \\  const dispatch = createEventDispatcher();
    \\  let isEditing = false;
    \\  let formData = { ...user };
    \\  
    \\  function handleEdit() {
    \\    isEditing = true;
    \\  }
    \\  
    \\  function handleSave() {
    \\    dispatch('save', formData);
    \\    isEditing = false;
    \\  }
    \\  
    \\  onMount(() => {
    \\    console.log('UserCard component mounted');
    \\  });
    \\</script>
    \\
    \\<style>
    \\  .user-card {
    \\    --card-bg: #ffffff;
    \\    --card-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
    \\    
    \\    background: var(--card-bg);
    \\    border-radius: 8px;
    \\    padding: 1.5rem;
    \\    box-shadow: var(--card-shadow);
    \\  }
    \\  
    \\  .user-name {
    \\    font-size: 1.5rem;
    \\    font-weight: 600;
    \\    margin-bottom: 0.5rem;
    \\  }
    \\  
    \\  .user-email {
    \\    color: #666;
    \\    margin-bottom: 1rem;
    \\  }
    \\  
    \\  button {
    \\    background: #007bff;
    \\    color: white;
    \\    border: none;
    \\    padding: 0.5rem 1rem;
    \\    border-radius: 4px;
    \\    cursor: pointer;
    \\  }
    \\</style>
    \\
    \\<div class="user-card">
    \\  {#if isEditing}
    \\    <input bind:value={formData.name} class="user-name" />
    \\    <input bind:value={formData.email} class="user-email" />
    \\    <button on:click={handleSave}>Save</button>
    \\    <button on:click={() => isEditing = false}>Cancel</button>
    \\  {:else}
    \\    <h2 class="user-name">{user.name}</h2>
    \\    <p class="user-email">{user.email}</p>
    \\    {#if editable}
    \\      <button on:click={handleEdit}>Edit</button>
    \\    {/if}
    \\  {/if}
    \\</div>
;