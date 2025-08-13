#!/bin/bash
# Terminal demo of zz parsing capabilities

set -e

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

clear
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║            zz Terminal Demo - Language Parsing              ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo

# Demo function
demo() {
    echo -e "\n${BOLD}${BLUE}$1${NC}"
    echo -e "${YELLOW}$ $2${NC}"
    echo
    eval "$2"
    echo
    read -p "Press Enter to continue..."
}

# Tree visualization
demo "1. Directory Tree Visualization" \
    "./zig-out/bin/zz tree demo --no-gitignore"

# TypeScript parsing
echo -e "\n${BOLD}Creating sample TypeScript file...${NC}"
cat > /tmp/demo.ts << 'EOF'
interface User {
    id: number;
    name: string;
    email: string;
}

class UserService {
    async getUser(id: number): Promise<User> {
        return await fetch(`/api/users/${id}`);
    }
}

export { User, UserService };
EOF

demo "2. Parse TypeScript - Extract Signatures & Types" \
    "./zig-out/bin/zz prompt /tmp/demo.ts --signatures --types"

# CSS parsing
echo -e "\n${BOLD}Creating sample CSS file...${NC}"
cat > /tmp/demo.css << 'EOF'
:root {
    --primary-color: #007bff;
    --secondary-color: #6c757d;
}

.container {
    display: grid;
    background: var(--primary-color);
}

@media (max-width: 768px) {
    .container { grid-template-columns: 1fr; }
}
EOF

demo "3. Parse CSS - Extract Structure" \
    "./zig-out/bin/zz prompt /tmp/demo.css --signatures --types"

# Performance
demo "4. Performance Benchmarks" \
    "./zig-out/bin/zz benchmark --format=pretty --duration=500ms"

echo -e "${BOLD}${GREEN}Demo Complete!${NC}"
echo -e "\n${BOLD}Key Takeaways:${NC}"
echo "• Terminal-only rendering with ANSI colors"
echo "• Fast language parsing (TypeScript, CSS, HTML, JSON, Svelte)"
echo "• 20-30% faster than stdlib for path operations"
echo "• Pattern matching at ~25ns per operation"

# Cleanup
rm -f /tmp/demo.ts /tmp/demo.css