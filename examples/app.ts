// TypeScript Application Example
// @ts-expect-error
import { Database } from './database.ts';
// @ts-expect-error
import { Logger } from './logger.ts';

interface User {
    id: number;
    name: string;
    email: string;
    role: UserRole;
    createdAt: Date;
}

type UserRole = 'admin' | 'editor' | 'viewer';

interface ApiResponse<T> {
    data: T;
    status: number;
    message?: string;
}

class UserService {
    private db: Database;
    private logger: Logger;
    
    constructor(database: Database) {
        this.db = database;
        this.logger = new Logger('UserService');
    }
    
    async getUser(id: number): Promise<User> {
        this.logger.info(`Fetching user ${id}`);
        return await this.db.findOne<User>('users', { id });
    }
    
    async createUser(data: Partial<User>): Promise<ApiResponse<User>> {
        try {
            const user = await this.db.insert<User>('users', {
                ...data,
                createdAt: new Date()
            });
            
            return {
                data: user,
                status: 201,
                message: 'User created successfully'
            };
        } catch (error) {
            this.logger.error('Failed to create user', error);
            throw error;
        }
    }
    
    async updateUserRole(userId: number, role: UserRole): Promise<void> {
        await this.db.update('users', { id: userId }, { role });
    }
}

export { UserService, User, UserRole, ApiResponse };