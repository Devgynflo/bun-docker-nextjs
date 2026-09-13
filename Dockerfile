FROM oven/bun:1

WORKDIR /app

# Installe les dépendances séparément pour profiter du cache Docker
COPY package.json bun.lock* ./
RUN bun install

# Copie le reste du code
COPY . .

EXPOSE 3000

CMD ["bun", "run", "dev"]