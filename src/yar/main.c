#include "../raylib/include/raylib.h"
#include <math.h>

#define SCREEN_WIDTH 800
#define SCREEN_HEIGHT 600
#define PLAYER_SPEED 200.0f
#define BULLET_SPEED 400.0f
#define ENEMY_SPEED 100.0f
#define MAX_BULLETS 20
#define MAX_ENEMIES 10

typedef struct {
    Vector2 position;
    Vector2 velocity;
    float radius;
    bool active;
    Color color;
} GameObject;

typedef struct {
    GameObject player;
    GameObject bullets[MAX_BULLETS];
    GameObject enemies[MAX_ENEMIES];
    int score;
    bool gameOver;
} GameState;

void InitGame(GameState *game) {
    // Initialize player
    game->player.position = (Vector2){ SCREEN_WIDTH/2, SCREEN_HEIGHT/2 };
    game->player.velocity = (Vector2){ 0, 0 };
    game->player.radius = 20.0f;
    game->player.active = true;
    game->player.color = BLUE;
    
    // Initialize bullets
    for (int i = 0; i < MAX_BULLETS; i++) {
        game->bullets[i].active = false;
        game->bullets[i].radius = 5.0f;
        game->bullets[i].color = YELLOW;
    }
    
    // Initialize enemies
    for (int i = 0; i < MAX_ENEMIES; i++) {
        game->enemies[i].position = (Vector2){ 
            GetRandomValue(0, SCREEN_WIDTH), 
            GetRandomValue(0, SCREEN_HEIGHT) 
        };
        game->enemies[i].velocity = (Vector2){ 0, 0 };
        game->enemies[i].radius = 15.0f;
        game->enemies[i].active = true;
        game->enemies[i].color = RED;
    }
    
    game->score = 0;
    game->gameOver = false;
}

void UpdatePlayer(GameState *game, float deltaTime) {
    Vector2 movement = { 0, 0 };
    
    if (IsKeyDown(KEY_W) || IsKeyDown(KEY_UP)) movement.y -= 1;
    if (IsKeyDown(KEY_S) || IsKeyDown(KEY_DOWN)) movement.y += 1;
    if (IsKeyDown(KEY_A) || IsKeyDown(KEY_LEFT)) movement.x -= 1;
    if (IsKeyDown(KEY_D) || IsKeyDown(KEY_RIGHT)) movement.x += 1;
    
    // Normalize diagonal movement
    if (movement.x != 0 && movement.y != 0) {
        movement.x *= 0.707f;
        movement.y *= 0.707f;
    }
    
    // Update position
    game->player.position.x += movement.x * PLAYER_SPEED * deltaTime;
    game->player.position.y += movement.y * PLAYER_SPEED * deltaTime;
    
    // Keep player on screen
    if (game->player.position.x < game->player.radius) 
        game->player.position.x = game->player.radius;
    if (game->player.position.x > SCREEN_WIDTH - game->player.radius) 
        game->player.position.x = SCREEN_WIDTH - game->player.radius;
    if (game->player.position.y < game->player.radius) 
        game->player.position.y = game->player.radius;
    if (game->player.position.y > SCREEN_HEIGHT - game->player.radius) 
        game->player.position.y = SCREEN_HEIGHT - game->player.radius;
}

void FireBullet(GameState *game) {
    Vector2 mousePos = GetMousePosition();
    Vector2 direction = {
        mousePos.x - game->player.position.x,
        mousePos.y - game->player.position.y
    };
    
    float length = sqrtf(direction.x * direction.x + direction.y * direction.y);
    if (length > 0) {
        direction.x /= length;
        direction.y /= length;
    }
    
    // Find inactive bullet
    for (int i = 0; i < MAX_BULLETS; i++) {
        if (!game->bullets[i].active) {
            game->bullets[i].position = game->player.position;
            game->bullets[i].velocity.x = direction.x * BULLET_SPEED;
            game->bullets[i].velocity.y = direction.y * BULLET_SPEED;
            game->bullets[i].active = true;
            break;
        }
    }
}

void UpdateBullets(GameState *game, float deltaTime) {
    for (int i = 0; i < MAX_BULLETS; i++) {
        if (game->bullets[i].active) {
            game->bullets[i].position.x += game->bullets[i].velocity.x * deltaTime;
            game->bullets[i].position.y += game->bullets[i].velocity.y * deltaTime;
            
            // Deactivate if off screen
            if (game->bullets[i].position.x < 0 || game->bullets[i].position.x > SCREEN_WIDTH ||
                game->bullets[i].position.y < 0 || game->bullets[i].position.y > SCREEN_HEIGHT) {
                game->bullets[i].active = false;
            }
        }
    }
}

void UpdateEnemies(GameState *game, float deltaTime) {
    for (int i = 0; i < MAX_ENEMIES; i++) {
        if (game->enemies[i].active) {
            // Move towards player
            Vector2 direction = {
                game->player.position.x - game->enemies[i].position.x,
                game->player.position.y - game->enemies[i].position.y
            };
            
            float length = sqrtf(direction.x * direction.x + direction.y * direction.y);
            if (length > 0) {
                direction.x /= length;
                direction.y /= length;
            }
            
            game->enemies[i].position.x += direction.x * ENEMY_SPEED * deltaTime;
            game->enemies[i].position.y += direction.y * ENEMY_SPEED * deltaTime;
        }
    }
}

void CheckCollisions(GameState *game) {
    // Bullet-Enemy collisions
    for (int i = 0; i < MAX_BULLETS; i++) {
        if (game->bullets[i].active) {
            for (int j = 0; j < MAX_ENEMIES; j++) {
                if (game->enemies[j].active) {
                    float distance = sqrtf(
                        (game->bullets[i].position.x - game->enemies[j].position.x) * 
                        (game->bullets[i].position.x - game->enemies[j].position.x) +
                        (game->bullets[i].position.y - game->enemies[j].position.y) * 
                        (game->bullets[i].position.y - game->enemies[j].position.y)
                    );
                    
                    if (distance < game->bullets[i].radius + game->enemies[j].radius) {
                        game->bullets[i].active = false;
                        game->enemies[j].active = false;
                        game->score += 10;
                        
                        // Respawn enemy at random edge
                        int edge = GetRandomValue(0, 3);
                        switch (edge) {
                            case 0: // Top
                                game->enemies[j].position = (Vector2){ GetRandomValue(0, SCREEN_WIDTH), -50 };
                                break;
                            case 1: // Right
                                game->enemies[j].position = (Vector2){ SCREEN_WIDTH + 50, GetRandomValue(0, SCREEN_HEIGHT) };
                                break;
                            case 2: // Bottom
                                game->enemies[j].position = (Vector2){ GetRandomValue(0, SCREEN_WIDTH), SCREEN_HEIGHT + 50 };
                                break;
                            case 3: // Left
                                game->enemies[j].position = (Vector2){ -50, GetRandomValue(0, SCREEN_HEIGHT) };
                                break;
                        }
                        game->enemies[j].active = true;
                    }
                }
            }
        }
    }
    
    // Player-Enemy collisions
    for (int i = 0; i < MAX_ENEMIES; i++) {
        if (game->enemies[i].active) {
            float distance = sqrtf(
                (game->player.position.x - game->enemies[i].position.x) * 
                (game->player.position.x - game->enemies[i].position.x) +
                (game->player.position.y - game->enemies[i].position.y) * 
                (game->player.position.y - game->enemies[i].position.y)
            );
            
            if (distance < game->player.radius + game->enemies[i].radius) {
                game->gameOver = true;
            }
        }
    }
}

void DrawGame(GameState *game) {
    BeginDrawing();
    ClearBackground(BLACK);
    
    if (!game->gameOver) {
        // Draw player
        DrawCircleV(game->player.position, game->player.radius, game->player.color);
        
        // Draw bullets
        for (int i = 0; i < MAX_BULLETS; i++) {
            if (game->bullets[i].active) {
                DrawCircleV(game->bullets[i].position, game->bullets[i].radius, game->bullets[i].color);
            }
        }
        
        // Draw enemies
        for (int i = 0; i < MAX_ENEMIES; i++) {
            if (game->enemies[i].active) {
                DrawCircleV(game->enemies[i].position, game->enemies[i].radius, game->enemies[i].color);
            }
        }
        
        // Draw UI
        DrawText(TextFormat("Score: %d", game->score), 10, 10, 20, WHITE);
        DrawText("WASD/Arrows: Move", 10, SCREEN_HEIGHT - 60, 16, GRAY);
        DrawText("Mouse: Aim & Click to Shoot", 10, SCREEN_HEIGHT - 40, 16, GRAY);
        DrawText("ESC: Quit", 10, SCREEN_HEIGHT - 20, 16, GRAY);
    } else {
        // Game over screen
        DrawText("GAME OVER", SCREEN_WIDTH/2 - 100, SCREEN_HEIGHT/2 - 50, 40, RED);
        DrawText(TextFormat("Final Score: %d", game->score), SCREEN_WIDTH/2 - 80, SCREEN_HEIGHT/2, 20, WHITE);
        DrawText("Press R to restart or ESC to quit", SCREEN_WIDTH/2 - 140, SCREEN_HEIGHT/2 + 40, 16, GRAY);
    }
    
    EndDrawing();
}

int main(void) {
    InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "YAR - Yet Another Raider");
    SetTargetFPS(60);
    
    GameState game;
    InitGame(&game);
    
    while (!WindowShouldClose()) {
        float deltaTime = GetFrameTime();
        
        if (!game.gameOver) {
            UpdatePlayer(&game, deltaTime);
            
            if (IsMouseButtonPressed(MOUSE_BUTTON_LEFT)) {
                FireBullet(&game);
            }
            
            UpdateBullets(&game, deltaTime);
            UpdateEnemies(&game, deltaTime);
            CheckCollisions(&game);
        } else {
            if (IsKeyPressed(KEY_R)) {
                InitGame(&game);
            }
        }
        
        if (IsKeyPressed(KEY_ESCAPE)) break;
        
        DrawGame(&game);
    }
    
    CloseWindow();
    return 0;
}
