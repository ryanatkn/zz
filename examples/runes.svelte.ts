// Svelte 5 Reactive Component with TypeScript
// Using runes for reactive state management

import { type Snippet } from 'svelte';

// Type definitions
interface TodoItem {
    id: number;
    text: string;
    completed: boolean;
    createdAt: Date;
}

interface TodoStats {
    total: number;
    completed: number;
    pending: number;
    completionRate: number;
}

// Props interface
interface TodoListProps {
    initialTodos?: TodoItem[];
    onStatsChange?: (stats: TodoStats) => void;
    children?: Snippet;
}

// Main component class with reactive state
export class TodoList {
    // Reactive state using $state rune
    todos = $state<TodoItem[]>([]);
    filter = $state<'all' | 'active' | 'completed'>('all');
    newTodoText = $state('');
    
    // Derived state using $derived rune
    filteredTodos = $derived(() => {
        switch (this.filter) {
            case 'active':
                return this.todos.filter(t => !t.completed);
            case 'completed':
                return this.todos.filter(t => t.completed);
            default:
                return this.todos;
        }
    });
    
    stats = $derived<TodoStats>(() => {
        const total = this.todos.length;
        const completed = this.todos.filter(t => t.completed).length;
        return {
            total,
            completed,
            pending: total - completed,
            completionRate: total > 0 ? (completed / total) * 100 : 0
        };
    });
    
    // Effects using $effect rune
    $effect(() => {
        console.log(`Todo count changed: ${this.todos.length}`);
    });
    
    $effect.pre(() => {
        // Runs before DOM updates
        if (this.stats.completionRate === 100) {
            console.log('All todos completed!');
        }
    });
    
    // Methods
    addTodo() {
        if (this.newTodoText.trim()) {
            this.todos = [...this.todos, {
                id: Date.now(),
                text: this.newTodoText,
                completed: false,
                createdAt: new Date()
            }];
            this.newTodoText = '';
        }
    }
    
    toggleTodo(id: number) {
        this.todos = this.todos.map(todo =>
            todo.id === id ? { ...todo, completed: !todo.completed } : todo
        );
    }
    
    deleteTodo(id: number) {
        this.todos = this.todos.filter(todo => todo.id !== id);
    }
    
    clearCompleted() {
        this.todos = this.todos.filter(todo => !todo.completed);
    }
    
    // Lifecycle
    constructor(props: TodoListProps) {
        if (props.initialTodos) {
            this.todos = props.initialTodos;
        }
        
        // Watch for stats changes
        $effect(() => {
            props.onStatsChange?.(this.stats);
        });
    }
}

// Store for global state management
export const globalTodoStore = $state({
    todos: [] as TodoItem[],
    lastSync: null as Date | null,
    
    async syncWithServer() {
        try {
            const response = await fetch('/api/todos');
            this.todos = await response.json();
            this.lastSync = new Date();
        } catch (error) {
            console.error('Sync failed:', error);
        }
    }
});

// Composable for todo logic
export function useTodos() {
    const todos = $state<TodoItem[]>([]);
    const loading = $state(false);
    const error = $state<string | null>(null);
    
    async function loadTodos() {
        loading = true;
        error = null;
        try {
            const response = await fetch('/api/todos');
            if (!response.ok) throw new Error('Failed to load');
            todos = await response.json();
        } catch (e) {
            error = e instanceof Error ? e.message : 'Unknown error';
        } finally {
            loading = false;
        }
    }
    
    return {
        todos: $derived(() => todos),
        loading: $derived(() => loading),
        error: $derived(() => error),
        loadTodos
    };
}

// Advanced reactive patterns
export class ReactiveCounter {
    // Private reactive state
    #count = $state(0);
    #history = $state<number[]>([]);
    
    // Public getters using $derived
    count = $derived(() => this.#count);
    doubleCount = $derived(() => this.#count * 2);
    average = $derived(() => {
        if (this.#history.length === 0) return 0;
        return this.#history.reduce((a, b) => a + b, 0) / this.#history.length;
    });
    
    // Methods with reactive updates
    increment() {
        this.#count++;
        this.#history = [...this.#history, this.#count];
    }
    
    decrement() {
        this.#count--;
        this.#history = [...this.#history, this.#count];
    }
    
    reset() {
        this.#count = 0;
        this.#history = [0];
    }
}

// Type-safe event handlers
export interface TodoEvents {
    onAdd: (todo: TodoItem) => void;
    onToggle: (id: number, completed: boolean) => void;
    onDelete: (id: number) => void;
    onBulkAction: (action: 'clear' | 'complete-all') => void;
}

// Async reactive state
export class AsyncDataLoader<T> {
    data = $state<T | null>(null);
    loading = $state(false);
    error = $state<Error | null>(null);
    
    constructor(private fetcher: () => Promise<T>) {
        this.load();
    }
    
    async load() {
        this.loading = true;
        this.error = null;
        try {
            this.data = await this.fetcher();
        } catch (e) {
            this.error = e instanceof Error ? e : new Error('Unknown error');
        } finally {
            this.loading = false;
        }
    }
    
    async refresh() {
        await this.load();
    }
}