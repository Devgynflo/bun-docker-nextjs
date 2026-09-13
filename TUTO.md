# Tuto : tester Next.js avec Bun sous Docker

Ce tutoriel vous fait créer, depuis un dossier vide, une application Next.js
exécutée avec Bun à l'intérieur d'un conteneur Docker.

## Prérequis

- Docker Desktop installé et **lancé** (vérifiez avec `docker info`, la
  commande ne doit pas renvoyer d'erreur).
- Un terminal, positionné dans le dossier du projet :

```bash
cd /Users/gynflo/Documents/bun-docker-nextjs
```

---

## Étape 1 — Générer l'app avec `bun create next-app`

Pas besoin d'installer Bun ni Node sur votre machine : on lance la commande
officielle `bun create next-app` **à l'intérieur d'un conteneur** `oven/bun`,
avec le dossier courant monté en volume.

```bash
docker run --rm -it -v "$(pwd)":/app -w /app oven/bun:1 bun create next-app .
```

> ⚠️ Le générateur refuse de s'exécuter si le dossier contient déjà des
> fichiers (par exemple ce `TUTO.md`). Sortez-le temporairement avant de
> lancer la commande, puis remettez-le une fois l'app générée :
>
> ```bash
> mv TUTO.md /tmp/TUTO.md
> docker run --rm -it -v "$(pwd)":/app -w /app oven/bun:1 bun create next-app .
> mv /tmp/TUTO.md TUTO.md
> ```

Cette commande est **interactive** : elle pose quelques questions dans le
terminal. Vous pouvez valider les choix par défaut avec `Entrée`, ou répondre
`Yes`/`No` selon vos préférences :

```
✔ Would you like to use TypeScript? … Yes
✔ Would you like to use ESLint? … Yes
✔ Would you like to use Tailwind CSS? … Yes
✔ Would you like your code inside a `src/` directory? … No
✔ Would you like to use App Router? … Yes
✔ Would you like to use Turbopack for `next dev`? … Yes
✔ Would you like to customize the import alias? … No
```

À la fin, votre dossier contient : `app/`, `public/`, `package.json`,
`next.config.ts`, `tsconfig.json`, `bun.lock`, etc. — l'app Next.js est prête.

Si les fichiers générés appartiennent à `root` (résidu du conteneur),
récupérez-en la propriété :

```bash
sudo chown -R "$(id -un)":"$(id -gn)" .
```

---

## Étape 2 — Créer le `Dockerfile`

Créez un fichier `Dockerfile` à la racine du projet avec ce contenu :

```dockerfile
FROM oven/bun:1

WORKDIR /app

# Installe les dépendances séparément pour profiter du cache Docker
COPY package.json bun.lock* ./
RUN bun install

# Copie le reste du code
COPY . .

EXPOSE 3000

CMD ["bun", "run", "dev"]
```

---

## Étape 3 — Créer le `.dockerignore`

Créez un fichier `.dockerignore` :

```
node_modules
.next
.git
.env*
Dockerfile
docker-compose.yml
```

---

## Étape 4 — Créer le `docker-compose.yml`

Créez un fichier `docker-compose.yml` à la racine :

```yaml
services:
  web:
    build: .
    ports:
      - "3000:3000"
    volumes:
      - .:/app
      - /app/node_modules
      - /app/.next
    environment:
      - WATCHPACK_POLLING=true
    command: bun run dev
```

- `volumes: .:/app` : monte votre code source dans le conteneur pour que les
  modifications soient prises en compte sans reconstruire l'image
  (hot-reload).
- `/app/node_modules` et `/app/.next` en volumes anonymes : empêchent que le
  volume `.:/app` n'écrase les `node_modules` installés dans l'image par ceux
  (potentiellement absents ou différents) de votre machine hôte.
- `WATCHPACK_POLLING=true` : nécessaire sur certains systèmes (notamment
  macOS/Docker Desktop) pour que Next.js détecte les changements de fichiers
  à travers le volume monté.

---

## Étape 5 — Lancer le projet

```bash
docker compose up --build
```

- Premier lancement : l'image est construite (installation des dépendances
  via Bun), cela peut prendre une à deux minutes.
- Une fois prêt, vous verrez dans les logs quelque chose comme :
  `Ready in XXXms` et `Local: http://localhost:3000`.

Ouvrez ensuite votre navigateur sur **http://localhost:3000** : vous devez
voir la page d'accueil par défaut de Next.js.

Pour lancer en arrière-plan :

```bash
docker compose up --build -d
```

Pour suivre les logs ensuite :

```bash
docker compose logs -f web
```

---

## Étape 6 — Vérifier que ça fonctionne

Dans un second terminal :

```bash
curl -I http://localhost:3000
```

Vous devez obtenir un `HTTP/1.1 200 OK`.

Testez aussi le hot-reload : modifiez le texte dans `app/page.tsx`, sauvegardez,
et vérifiez que la page se met à jour automatiquement dans le navigateur.

---

## Étape 7 — Arrêter et nettoyer

```bash
docker compose down
```

Pour aussi supprimer l'image construite :

```bash
docker compose down --rmi local
```

---

## Étape 8 — Build de production

Le `Dockerfile` des étapes précédentes est pensé pour le **développement**
(hot-reload via volume monté). Pour la **production**, on veut une image plus
légère, sans code source ni outils de dev, qui contient uniquement l'app déjà
compilée.

### 8.1 — Activer la sortie `standalone` de Next.js

Dans `next.config.ts`, ajoutez l'option `output: "standalone"` :

```ts
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
};

export default nextConfig;
```

Cette option fait en sorte que `next build` génère, dans `.next/standalone`,
un serveur autonome ne dépendant que des fichiers strictement nécessaires à
l'exécution (au lieu de devoir embarquer tout `node_modules`).

### 8.2 — Créer `Dockerfile.prod`

Ce Dockerfile utilise un **build multi-étapes** : une étape pour installer
les dépendances, une pour builder l'app, et une dernière, minimale, qui ne
contient que le résultat du build.

```dockerfile
# --- Étape 1 : installation des dépendances ---
FROM oven/bun:1 AS deps
WORKDIR /app
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile

# --- Étape 2 : build de l'application ---
FROM oven/bun:1 AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN bun run build

# --- Étape 3 : image finale, minimale ---
FROM oven/bun:1 AS runner
WORKDIR /app
ENV NODE_ENV=production

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

EXPOSE 3000

CMD ["bun", "server.js"]
```

- `--frozen-lockfile` : garantit que le build utilise exactement les versions
  du `bun.lock`, sans jamais le modifier (comportement attendu en CI/prod).
- La dernière étape ne copie que `public/`, `.next/standalone` et
  `.next/static` : pas de `node_modules` complet, pas de code source, pas de
  devDependencies → image bien plus petite.

### 8.3 — Créer `docker-compose.prod.yml`

```yaml
services:
  web:
    build:
      context: .
      dockerfile: Dockerfile.prod
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
    restart: unless-stopped
```

Pas de volumes ici : en prod, le code vit **dans** l'image, il n'y a pas de
hot-reload.

### 8.4 — Builder et lancer en production

```bash
docker compose -f docker-compose.prod.yml up --build -d
```

Vérifiez que ça répond :

```bash
curl -I http://localhost:3000
```

Consultez les logs :

```bash
docker compose -f docker-compose.prod.yml logs -f web
```

Arrêtez / nettoyez :

```bash
docker compose -f docker-compose.prod.yml down
```

### 8.5 — Comparer la taille des images

```bash
docker images | grep bun-docker-nextjs
```

L'image construite avec `Dockerfile.prod` doit être nettement plus légère que
celle construite avec le `Dockerfile` de dev (pas de `node_modules` complet,
pas de code source non compilé).

---

## Étape 9 — Déployer sur un VPS avec Coolify

Coolify est une plateforme auto-hébergée qui construit et déploie vos apps à
partir d'un dépôt Git (elle utilise Docker en interne). On va lui faire
construire l'image de production (`Dockerfile.prod`) et l'exposer via son
proxy intégré (Traefik), avec HTTPS automatique si vous avez un domaine.

### 9.1 — Prérequis

- Un VPS avec **Coolify déjà installé** et accessible via son interface web.
- Le projet poussé sur un **dépôt Git distant** accessible depuis le VPS
  (GitHub, GitLab, ou le serveur Git intégré à Coolify). Coolify a besoin de
  cloner le repo pour builder — un simple transfert de fichiers ne suffit pas.
- (Optionnel) Un nom de domaine pointant vers l'IP du VPS, si vous voulez du
  HTTPS automatique plutôt que d'utiliser l'IP:port directement.

### 9.2 — Pousser le projet sur un dépôt Git

Si ce n'est pas déjà fait :

```bash
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin <url-de-votre-repo>
git push -u origin main
```

Vérifiez que `.gitignore` exclut bien `node_modules` et `.next` (c'est le cas
par défaut, généré à l'étape 1).

### 9.3 — Créer une nouvelle application dans Coolify

Dans l'interface Coolify :

1. **New Resource → Application**.
2. Choisissez la source : **Public/Private Git Repository**, puis
   sélectionnez votre dépôt et la branche (`main`).
3. **Build Pack** : choisissez **Dockerfile**.
4. **Dockerfile location** : `Dockerfile.prod` (pas le `Dockerfile` de dev).
5. **Ports Exposes** : `3000` (c'est le port sur lequel `bun server.js`
   écoute, cf. `EXPOSE 3000` dans `Dockerfile.prod`).

### 9.4 — Configurer le domaine / l'accès

- Si vous avez un domaine : renseignez-le dans **Domains**, Coolify génère
  automatiquement un certificat HTTPS (Let's Encrypt) via son proxy Traefik.
- Sinon, Coolify vous donne une URL type `http://<ip-du-vps>:<port-généré>`
  pour tester directement.

### 9.5 — Variables d'environnement

Dans l'onglet **Environment Variables** de l'application Coolify, ajoutez au
minimum :

```
NODE_ENV=production
```

Ajoutez ici toute autre variable dont votre app aurait besoin (clés API,
URL de base de données, etc.) — Coolify les injecte au conteneur au démarrage.

### 9.6 — Déployer

Cliquez sur **Deploy**. Coolify va :

1. Cloner le dépôt.
2. Builder l'image à partir de `Dockerfile.prod` (les 3 étapes : deps → build
   → runner).
3. Démarrer le conteneur et le relier à son proxy.

Suivez la progression dans l'onglet **Logs / Deployments**.

### 9.7 — Vérifier

Une fois le déploiement marqué **Running** :

- Ouvrez l'URL/domaine configuré dans un navigateur.
- Ou depuis un terminal ayant accès au VPS :

```bash
curl -I https://votre-domaine.example
```

Vous devez obtenir un `HTTP/2 200`.

### 9.8 — Redéploiement automatique

Dans **Webhooks** (ou **Automatic Deployment**), activez le webhook Git
proposé par Coolify et ajoutez-le dans les paramètres de votre dépôt
(GitHub/GitLab → Webhooks). À chaque `git push` sur la branche configurée,
Coolify rebuild et redéploie automatiquement.

### 9.9 — Dépannage spécifique Coolify

| Problème | Piste |
|---|---|
| Build échoue sur `bun install` | Vérifiez que `bun.lock` est bien commité dans le dépôt Git. |
| **502 Bad Gateway** alors que le conteneur est "Running" | Cause la plus fréquente : Docker positionne automatiquement `HOSTNAME=<id du conteneur>`, et le serveur standalone de Next.js écoute sur cette valeur au lieu de `0.0.0.0`, le rendant injoignable par le proxy. Le `Dockerfile.prod` de ce tuto force déjà `ENV HOSTNAME="0.0.0.0"` — si vous êtes toujours bloqué, vérifiez côté VPS avec `docker logs <conteneur>` et `docker exec -it <conteneur> curl -I http://localhost:3000` (voir détail ci-dessous). |
| App "Running" mais inaccessible | Vérifiez que **Ports Exposes** = `3000` et que le domaine/DNS pointe bien vers le VPS. |
| Pas de HTTPS | Un domaine valide (DNS propagé) est nécessaire pour que Traefik obtienne un certificat Let's Encrypt. |
| Changements non pris en compte après un push | Vérifiez que le webhook est bien configuré, ou redéployez manuellement depuis Coolify. |

**Diagnostiquer un Bad Gateway pas à pas** (en SSH sur le VPS) :

```bash
# 1. Trouver le conteneur de l'app
docker ps -a | grep <uuid-de-la-resource-coolify>

# 2. Logs runtime (pas les logs de build affichés dans l'UI Coolify)
docker logs --tail 100 <nom-du-conteneur>

# 3. Vérifier que l'app répond depuis l'intérieur du conteneur
docker exec -it <nom-du-conteneur> curl -I http://localhost:3000

# 4. Vérifier qu'il est bien sur le réseau "coolify" utilisé par le proxy
docker inspect <nom-du-conteneur> --format '{{json .NetworkSettings.Networks}}'
```

Si l'étape 3 échoue déjà (même en interne), le problème vient du serveur
Next.js lui-même (`HOSTNAME`, crash au démarrage...). Si l'étape 3 réussit
mais que ça reste en Bad Gateway depuis l'extérieur, le problème vient de la
configuration du proxy/réseau Coolify (étape 4, ou **Ports Exposes** mal
configuré).

---

## Résumé des fichiers créés

```
bun-docker-nextjs/
├── app/                      # code de l'application Next.js (généré à l'étape 1)
├── public/
├── package.json
├── bun.lock
├── next.config.ts           # output: "standalone" (étape 8)
├── Dockerfile                # image Bun + serveur de dev (hot-reload)
├── Dockerfile.prod           # build multi-étapes pour la prod (étape 8)
├── docker-compose.yml        # orchestration dev
├── docker-compose.prod.yml   # orchestration prod (étape 8)
├── .dockerignore
└── TUTO.md                   # ce tutoriel
```

## Dépannage rapide

| Problème | Piste |
|---|---|
| `Cannot connect to the Docker daemon` | Lancez Docker Desktop et attendez qu'il soit prêt. |
| Le hot-reload ne fonctionne pas | Vérifiez que `WATCHPACK_POLLING=true` est bien présent dans `docker-compose.yml`. |
| Port 3000 déjà utilisé | Changez le mapping en `"3001:3000"` dans `docker-compose.yml` puis relancez. |
| Fichiers générés appartenant à `root` | `sudo chown -R "$(id -un)":"$(id -gn)" .` |
