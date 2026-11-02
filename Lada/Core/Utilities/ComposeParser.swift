import Foundation

// MARK: - Compose Stack Models

public struct ComposeServiceSpec: Identifiable, Codable, Sendable, Equatable {
    public var id: String { serviceName }
    public var serviceName: String
    public var containerName: String
    public var imageReference: String
    public var buildContext: String?
    public var publishedPorts: [PortMapping]
    public var environment: [KeyValueEntry]
    public var volumes: [MountAttachment]
    public var commandOverride: String
    public var workingDirectory: String
    public var dependsOn: [String]
    public var networks: [String]
    /// `networks: <name>: aliases:` entries (all networks combined; Låda deploys a stack on one network).
    public var networkAliases: [String]
    /// `mem_limit:` in MiB (e.g. `2g` → 2048); nil uses the app's default container memory.
    public var memoryLimitMB: Int?
    /// `cpus:` rounded up to whole vCPUs (the runtime allots whole CPUs); nil uses the default.
    public var cpuLimit: Int?

    public init(
        serviceName: String,
        containerName: String,
        imageReference: String,
        buildContext: String? = nil,
        publishedPorts: [PortMapping] = [],
        environment: [KeyValueEntry] = [],
        volumes: [MountAttachment] = [],
        commandOverride: String = "",
        workingDirectory: String = "",
        dependsOn: [String] = [],
        networks: [String] = [],
        networkAliases: [String] = [],
        memoryLimitMB: Int? = nil,
        cpuLimit: Int? = nil
    ) {
        self.serviceName = serviceName
        self.containerName = containerName
        self.imageReference = imageReference
        self.buildContext = buildContext
        self.publishedPorts = publishedPorts
        self.environment = environment
        self.volumes = volumes
        self.commandOverride = commandOverride
        self.workingDirectory = workingDirectory
        self.dependsOn = dependsOn
        self.networks = networks
        self.networkAliases = networkAliases
        self.memoryLimitMB = memoryLimitMB
        self.cpuLimit = cpuLimit
    }
}

public struct ParsedComposeStack: Sendable, Equatable {
    public var projectName: String
    public var services: [ComposeServiceSpec]
    public var declaredNetworks: [String]
    public var declaredVolumes: [String]
    public var warnings: [String]

    public init(
        projectName: String,
        services: [ComposeServiceSpec] = [],
        declaredNetworks: [String] = [],
        declaredVolumes: [String] = [],
        warnings: [String] = []
    ) {
        self.projectName = projectName
        self.services = services
        self.declaredNetworks = declaredNetworks
        self.declaredVolumes = declaredVolumes
        self.warnings = warnings
    }

    /// Returns services ordered topologically so dependencies (`depends_on`) start first.
    public var topologicalServices: [ComposeServiceSpec] {
        var visited = Set<String>()
        var result: [ComposeServiceSpec] = []
        let map = Dictionary(uniqueKeysWithValues: services.map { ($0.serviceName, $0) })

        func visit(_ name: String) {
            guard !visited.contains(name), let svc = map[name] else { return }
            visited.insert(name)
            for dep in svc.dependsOn {
                visit(dep)
            }
            result.append(svc)
        }

        for svc in services {
            visit(svc.serviceName)
        }
        return result
    }
}

// MARK: - Starter Compose Templates

public struct ComposeStackTemplate: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let projectName: String
    public let yamlContent: String

    public static let allTemplates: [ComposeStackTemplate] = [
        ComposeStackTemplate(
            id: "web-postgres-redis",
            title: "Website + PostgreSQL + Redis",
            subtitle: "An nginx front end with a PostgreSQL database and a Redis cache",
            projectName: "nordic-web",
            yamlContent: """
            name: nordic-web

            services:
              db:
                image: docker.io/library/postgres:17-alpine
                container_name: nordic-postgres
                ports:
                  - "5432:5432"
                environment:
                  POSTGRES_USER: lada
                  POSTGRES_PASSWORD: {{secret:db}}
                  POSTGRES_DB: lada_app
                  PGDATA: /var/lib/postgresql/data/pgdata
                volumes:
                  - pgdata:/var/lib/postgresql/data

              redis:
                image: docker.io/library/redis:8-alpine
                container_name: nordic-redis
                ports:
                  - "6379:6379"

              web:
                image: docker.io/library/nginx:1.31-alpine
                container_name: nordic-frontend
                ports:
                  - "8088:80"
                depends_on:
                  - db
                  - redis

            volumes:
              pgdata:
            """
        ),
        ComposeStackTemplate(
            id: "wordpress-mysql",
            title: "WordPress + MySQL",
            subtitle: "A WordPress site on port 8085 with its MySQL database",
            projectName: "wp-studio",
            yamlContent: """
            name: wp-studio

            services:
              mysql:
                image: docker.io/library/mysql:8.4
                container_name: wp-mysql
                command: --datadir=/var/lib/mysql/data
                environment:
                  MYSQL_ROOT_PASSWORD: {{secret:root}}
                  MYSQL_DATABASE: wordpress
                  MYSQL_USER: wp_user
                  MYSQL_PASSWORD: {{secret:wpdb}}
                volumes:
                  - wp_db:/var/lib/mysql

              wordpress:
                image: docker.io/library/wordpress:php8.4-apache
                container_name: wp-web
                ports:
                  - "8085:80"
                environment:
                  WORDPRESS_DB_HOST: mysql:3306
                  WORDPRESS_DB_USER: wp_user
                  WORDPRESS_DB_PASSWORD: {{secret:wpdb}}
                  WORDPRESS_DB_NAME: wordpress
                depends_on:
                  - mysql

            volumes:
              wp_db:
            """
        ),
        ComposeStackTemplate(
            id: "postgres-adminer",
            title: "PostgreSQL + Adminer",
            subtitle: "A PostgreSQL database with a web admin UI on port 8084",
            projectName: "pg-admin",
            yamlContent: """
            name: pg-admin

            services:
              db:
                image: docker.io/library/postgres:17-alpine
                container_name: pg-admin-db
                ports:
                  - "5432:5432"
                environment:
                  POSTGRES_USER: admin
                  POSTGRES_PASSWORD: {{secret:db}}
                  POSTGRES_DB: app
                  PGDATA: /var/lib/postgresql/data/pgdata
                volumes:
                  - pg_admin_data:/var/lib/postgresql/data

              adminer:
                image: docker.io/library/adminer:standalone
                container_name: pg-admin-ui
                ports:
                  - "8084:8080"
                environment:
                  ADMINER_DEFAULT_SERVER: db
                depends_on:
                  - db

            volumes:
              pg_admin_data:
            """
        ),
        ComposeStackTemplate(
            id: "gitea-postgres",
            title: "Git server (Gitea + PostgreSQL)",
            subtitle: "Your own Git hosting with a web UI on port 3000 and SSH on 2222",
            projectName: "git-server",
            yamlContent: """
            name: git-server

            services:
              db:
                image: docker.io/library/postgres:17-alpine
                container_name: gitea-db
                environment:
                  POSTGRES_USER: gitea
                  POSTGRES_PASSWORD: {{secret:db}}
                  POSTGRES_DB: gitea
                  PGDATA: /var/lib/postgresql/data/pgdata
                volumes:
                  - gitea_db:/var/lib/postgresql/data

              gitea:
                image: docker.io/gitea/gitea:28
                container_name: gitea
                ports:
                  - "3000:3000"
                  - "2222:22"
                environment:
                  GITEA__database__DB_TYPE: postgres
                  GITEA__database__HOST: db:5432
                  GITEA__database__NAME: gitea
                  GITEA__database__USER: gitea
                  GITEA__database__PASSWD: {{secret:db}}
                volumes:
                  - gitea_data:/data
                depends_on:
                  - db

            volumes:
              gitea_db:
              gitea_data:
            """
        ),
        ComposeStackTemplate(
            id: "observability-prometheus-grafana",
            title: "Prometheus + Grafana",
            subtitle: "Metrics collection on port 9090 and dashboards on port 3001",
            projectName: "telemetry",
            yamlContent: """
            name: telemetry

            services:
              prometheus:
                image: docker.io/prom/prometheus:v3.15.1
                container_name: telemetry-prometheus
                ports:
                  - "9090:9090"

              grafana:
                image: docker.io/grafana/grafana:13.3.0
                container_name: telemetry-grafana
                ports:
                  - "3001:3000"
                environment:
                  GF_SECURITY_ADMIN_USER: admin
                  GF_SECURITY_ADMIN_PASSWORD: {{secret:grafana}}
                depends_on:
                  - prometheus
            """
        ),
        ComposeStackTemplate(
            id: "python-api-redis",
            title: "Python API + Redis",
            subtitle: "A small Python HTTP service on port 8000 next to a Redis store",
            projectName: "py-stack",
            yamlContent: """
            name: py-stack

            services:
              cache:
                image: docker.io/library/redis:8-alpine
                container_name: py-redis
                ports:
                  - "6380:6379"

              api:
                image: docker.io/library/python:3.13-slim
                container_name: py-api
                working_dir: /app
                command: python3 -m http.server 8000
                ports:
                  - "8000:8000"
                environment:
                  REDIS_URL: redis://cache:6379/0
                  PYTHONUNBUFFERED: "1"
                depends_on:
                  - cache
            """
        ),
        ComposeStackTemplate(
            id: "messaging-nats-valkey",
            title: "Messaging + cache (NATS + Valkey)",
            subtitle: "A NATS message bus on 4222 (monitoring on 8222) and a Valkey cache on 6381",
            projectName: "messaging",
            yamlContent: """
            name: messaging

            services:
              nats:
                image: docker.io/library/nats:2.15-alpine
                container_name: messaging-nats
                command: --jetstream --http_port 8222
                ports:
                  - "4222:4222"
                  - "8222:8222"

              cache:
                image: docker.io/valkey/valkey:9.0-alpine
                container_name: messaging-valkey
                ports:
                  - "6381:6379"
                volumes:
                  - valkey_data:/data

            volumes:
              valkey_data:
            """
        ),
        ComposeStackTemplate(
            id: "dev-tools-mailpit-registry",
            title: "Developer tools (Mailpit + registry)",
            subtitle: "An email-testing inbox on 8025 (SMTP 1025) and a private image registry on 5000",
            projectName: "dev-tools",
            yamlContent: """
            name: dev-tools

            services:
              mail:
                image: docker.io/axllent/mailpit:v1
                container_name: dev-mailpit
                ports:
                  - "8025:8025"
                  - "1025:1025"

              registry:
                image: docker.io/library/registry:3
                container_name: dev-registry
                ports:
                  - "5000:5000"
                volumes:
                  - registry_data:/var/lib/registry

            volumes:
              registry_data:
            """
        ),
        ComposeStackTemplate(
            id: "vault-dev",
            title: "Secrets manager (Vault, dev mode)",
            subtitle: "HashiCorp Vault in development mode on port 8200; data is kept in memory",
            projectName: "vault-dev",
            yamlContent: """
            name: vault-dev

            services:
              vault:
                image: docker.io/hashicorp/vault:2.2
                container_name: vault-dev
                ports:
                  - "8200:8200"
                environment:
                  VAULT_DEV_ROOT_TOKEN_ID: {{secret:token}}
                  VAULT_DEV_LISTEN_ADDRESS: 0.0.0.0:8200
            """
        ),
        ComposeStackTemplate(
            id: "lamp",
            title: "LAMP: PHP + MariaDB + phpMyAdmin",
            subtitle: "Apache with PHP 8.4 on port 8090, MariaDB, and phpMyAdmin on port 8091",
            projectName: "lamp",
            yamlContent: """
            name: lamp

            services:
              db:
                image: docker.io/library/mariadb:11.8
                container_name: lamp-mariadb
                command: --datadir=/var/lib/mysql/data
                environment:
                  MARIADB_ROOT_PASSWORD: {{secret:root}}
                  MARIADB_DATABASE: app
                  MARIADB_USER: app
                  MARIADB_PASSWORD: {{secret:db}}
                volumes:
                  - lamp_db:/var/lib/mysql

              web:
                image: docker.io/library/php:8.4-apache
                container_name: lamp-web
                command: sh -c "echo '<?php phpinfo();' > /var/www/html/index.php && exec apache2-foreground"
                ports:
                  - "8090:80"
                depends_on:
                  - db

              phpmyadmin:
                image: docker.io/library/phpmyadmin:5.2
                container_name: lamp-phpmyadmin
                ports:
                  - "8091:80"
                environment:
                  PMA_HOST: db
                depends_on:
                  - db

            volumes:
              lamp_db:
            """
        ),
        ComposeStackTemplate(
            id: "mongo-express",
            title: "MongoDB + Mongo Express",
            subtitle: "MongoDB 8 on port 27017 with the Mongo Express web UI on port 8092",
            projectName: "mongo-stack",
            yamlContent: """
            name: mongo-stack

            services:
              mongo:
                image: docker.io/library/mongo:8.0
                container_name: mongo-db
                ports:
                  - "27017:27017"
                environment:
                  MONGO_INITDB_ROOT_USERNAME: admin
                  MONGO_INITDB_ROOT_PASSWORD: {{secret:mongo}}
                volumes:
                  - mongo_data:/data/db

              mongo-express:
                image: docker.io/library/mongo-express:1.0
                container_name: mongo-express
                ports:
                  - "8092:8081"
                environment:
                  ME_CONFIG_MONGODB_URL: mongodb://admin:{{secret:mongo}}@mongo:27017/
                  ME_CONFIG_BASICAUTH_USERNAME: admin
                  ME_CONFIG_BASICAUTH_PASSWORD: {{secret:ui}}
                depends_on:
                  - mongo

            volumes:
              mongo_data:
            """
        ),
        ComposeStackTemplate(
            id: "ghost-mysql",
            title: "Ghost blog + MySQL",
            subtitle: "The Ghost publishing platform on port 2368 with its MySQL database",
            projectName: "ghost-blog",
            yamlContent: """
            name: ghost-blog

            services:
              db:
                image: docker.io/library/mysql:8.4
                container_name: ghost-mysql
                command: --datadir=/var/lib/mysql/data
                environment:
                  MYSQL_ROOT_PASSWORD: {{secret:db}}
                  MYSQL_DATABASE: ghost
                volumes:
                  - ghost_db:/var/lib/mysql

              ghost:
                image: docker.io/library/ghost:6-alpine
                container_name: ghost-web
                ports:
                  - "2368:2368"
                environment:
                  url: http://localhost:2368
                  database__client: mysql
                  database__connection__host: db
                  database__connection__user: root
                  database__connection__password: {{secret:db}}
                  database__connection__database: ghost
                volumes:
                  - ghost_content:/var/lib/ghost/content
                depends_on:
                  - db

            volumes:
              ghost_db:
              ghost_content:
            """
        ),
        ComposeStackTemplate(
            id: "nextcloud",
            title: "Nextcloud + PostgreSQL + Redis",
            subtitle: "Your own file sync and sharing cloud on port 8093",
            projectName: "nextcloud",
            yamlContent: """
            name: nextcloud

            services:
              db:
                image: docker.io/library/postgres:17-alpine
                container_name: nextcloud-db
                environment:
                  POSTGRES_USER: nextcloud
                  POSTGRES_PASSWORD: {{secret:db}}
                  POSTGRES_DB: nextcloud
                  PGDATA: /var/lib/postgresql/data/pgdata
                volumes:
                  - nextcloud_db:/var/lib/postgresql/data

              redis:
                image: docker.io/library/redis:8-alpine
                container_name: nextcloud-redis

              app:
                image: docker.io/library/nextcloud:31-apache
                container_name: nextcloud-app
                ports:
                  - "8093:80"
                environment:
                  POSTGRES_HOST: db
                  POSTGRES_DB: nextcloud
                  POSTGRES_USER: nextcloud
                  POSTGRES_PASSWORD: {{secret:db}}
                  REDIS_HOST: redis
                  NEXTCLOUD_ADMIN_USER: admin
                  NEXTCLOUD_ADMIN_PASSWORD: {{secret:admin}}
                  NEXTCLOUD_TRUSTED_DOMAINS: localhost
                volumes:
                  - nextcloud_html:/var/www/html
                depends_on:
                  - db
                  - redis

            volumes:
              nextcloud_db:
              nextcloud_html:
            """
        ),
        ComposeStackTemplate(
            id: "drupal-postgres",
            title: "Drupal + PostgreSQL",
            subtitle: "Drupal 11 on port 8094 with PostgreSQL; finish setup in the browser (database host: db)",
            projectName: "drupal",
            yamlContent: """
            name: drupal

            services:
              db:
                image: docker.io/library/postgres:17-alpine
                container_name: drupal-db
                environment:
                  POSTGRES_USER: drupal
                  POSTGRES_PASSWORD: {{secret:db}}
                  POSTGRES_DB: drupal
                  PGDATA: /var/lib/postgresql/data/pgdata
                volumes:
                  - drupal_db:/var/lib/postgresql/data

              drupal:
                image: docker.io/library/drupal:11-apache
                container_name: drupal-web
                ports:
                  - "8094:80"
                depends_on:
                  - db

            volumes:
              drupal_db:
            """
        ),
        ComposeStackTemplate(
            id: "joomla-mariadb",
            title: "Joomla + MariaDB",
            subtitle: "Joomla 5 on port 8095 with its MariaDB database",
            projectName: "joomla",
            yamlContent: """
            name: joomla

            services:
              db:
                image: docker.io/library/mariadb:11.8
                container_name: joomla-db
                command: --datadir=/var/lib/mysql/data
                environment:
                  MARIADB_ROOT_PASSWORD: {{secret:root}}
                  MARIADB_DATABASE: joomla
                  MARIADB_USER: joomla
                  MARIADB_PASSWORD: {{secret:db}}
                volumes:
                  - joomla_db:/var/lib/mysql

              joomla:
                image: docker.io/library/joomla:5-apache
                container_name: joomla-web
                ports:
                  - "8095:80"
                environment:
                  JOOMLA_DB_HOST: db
                  JOOMLA_DB_USER: joomla
                  JOOMLA_DB_PASSWORD: {{secret:db}}
                  JOOMLA_DB_NAME: joomla
                depends_on:
                  - db

            volumes:
              joomla_db:
            """
        ),
        ComposeStackTemplate(
            id: "directus-postgres",
            title: "Directus headless CMS + PostgreSQL",
            subtitle: "Directus on port 8055: an API and admin app over a PostgreSQL database",
            projectName: "directus",
            yamlContent: """
            name: directus

            services:
              db:
                image: docker.io/library/postgres:17-alpine
                container_name: directus-db
                environment:
                  POSTGRES_USER: directus
                  POSTGRES_PASSWORD: {{secret:db}}
                  POSTGRES_DB: directus
                  PGDATA: /var/lib/postgresql/data/pgdata
                volumes:
                  - directus_db:/var/lib/postgresql/data

              directus:
                image: docker.io/directus/directus:11
                container_name: directus-app
                ports:
                  - "8055:8055"
                environment:
                  SECRET: {{secret:key}}
                  DB_CLIENT: pg
                  DB_HOST: db
                  DB_PORT: "5432"
                  DB_DATABASE: directus
                  DB_USER: directus
                  DB_PASSWORD: {{secret:db}}
                  ADMIN_EMAIL: admin@example.com
                  ADMIN_PASSWORD: {{secret:admin}}
                depends_on:
                  - db

            volumes:
              directus_db:
            """
        ),
        ComposeStackTemplate(
            id: "n8n-postgres",
            title: "n8n workflow automation + PostgreSQL",
            subtitle: "n8n on port 5678 storing workflows in PostgreSQL",
            projectName: "n8n",
            yamlContent: """
            name: n8n

            services:
              db:
                image: docker.io/library/postgres:17-alpine
                container_name: n8n-db
                environment:
                  POSTGRES_USER: n8n
                  POSTGRES_PASSWORD: {{secret:db}}
                  POSTGRES_DB: n8n
                  PGDATA: /var/lib/postgresql/data/pgdata
                volumes:
                  - n8n_db:/var/lib/postgresql/data

              n8n:
                image: docker.io/n8nio/n8n:2.46.4
                container_name: n8n-app
                ports:
                  - "5678:5678"
                environment:
                  DB_TYPE: postgresdb
                  DB_POSTGRESDB_HOST: db
                  DB_POSTGRESDB_DATABASE: n8n
                  DB_POSTGRESDB_USER: n8n
                  DB_POSTGRESDB_PASSWORD: {{secret:db}}
                  N8N_SECURE_COOKIE: "false"
                depends_on:
                  - db

            volumes:
              n8n_db:
            """
        ),
        ComposeStackTemplate(
            id: "keycloak-postgres",
            title: "Keycloak identity + PostgreSQL",
            subtitle: "Keycloak single sign-on in development mode on port 8180",
            projectName: "keycloak",
            yamlContent: """
            name: keycloak

            services:
              db:
                image: docker.io/library/postgres:17-alpine
                container_name: keycloak-db
                environment:
                  POSTGRES_USER: keycloak
                  POSTGRES_PASSWORD: {{secret:db}}
                  POSTGRES_DB: keycloak
                  PGDATA: /var/lib/postgresql/data/pgdata
                volumes:
                  - keycloak_db:/var/lib/postgresql/data

              keycloak:
                image: quay.io/keycloak/keycloak:26.8.1
                container_name: keycloak-app
                command: start-dev
                ports:
                  - "8180:8080"
                environment:
                  KC_DB: postgres
                  KC_DB_URL: jdbc:postgresql://db:5432/keycloak
                  KC_DB_USERNAME: keycloak
                  KC_DB_PASSWORD: {{secret:db}}
                  KC_BOOTSTRAP_ADMIN_USERNAME: admin
                  KC_BOOTSTRAP_ADMIN_PASSWORD: {{secret:admin}}
                depends_on:
                  - db

            volumes:
              keycloak_db:
            """
        ),
        ComposeStackTemplate(
            id: "matomo-mariadb",
            title: "Matomo analytics + MariaDB",
            subtitle: "Privacy-friendly web analytics on port 8096",
            projectName: "matomo",
            yamlContent: """
            name: matomo

            services:
              db:
                image: docker.io/library/mariadb:11.8
                container_name: matomo-db
                command: --datadir=/var/lib/mysql/data
                environment:
                  MARIADB_ROOT_PASSWORD: {{secret:root}}
                  MARIADB_DATABASE: matomo
                  MARIADB_USER: matomo
                  MARIADB_PASSWORD: {{secret:db}}
                volumes:
                  - matomo_db:/var/lib/mysql

              matomo:
                image: docker.io/library/matomo:5-apache
                container_name: matomo-web
                ports:
                  - "8096:80"
                environment:
                  MATOMO_DATABASE_HOST: db
                  MATOMO_DATABASE_ADAPTER: mysql
                  MATOMO_DATABASE_USERNAME: matomo
                  MATOMO_DATABASE_PASSWORD: {{secret:db}}
                  MATOMO_DATABASE_DBNAME: matomo
                depends_on:
                  - db

            volumes:
              matomo_db:
            """
        ),
        ComposeStackTemplate(
            id: "metabase-postgres",
            title: "Metabase BI + PostgreSQL",
            subtitle: "Dashboards and questions over your data on port 3002",
            projectName: "metabase",
            yamlContent: """
            name: metabase

            services:
              db:
                image: docker.io/library/postgres:17-alpine
                container_name: metabase-db
                environment:
                  POSTGRES_USER: metabase
                  POSTGRES_PASSWORD: {{secret:db}}
                  POSTGRES_DB: metabase
                  PGDATA: /var/lib/postgresql/data/pgdata
                volumes:
                  - metabase_db:/var/lib/postgresql/data

              metabase:
                image: docker.io/metabase/metabase:v0.65.2.6
                container_name: metabase-app
                mem_limit: 2g
                ports:
                  - "3002:3000"
                environment:
                  MB_DB_TYPE: postgres
                  MB_DB_DBNAME: metabase
                  MB_DB_PORT: "5432"
                  MB_DB_USER: metabase
                  MB_DB_PASS: {{secret:db}}
                  MB_DB_HOST: db
                depends_on:
                  - db

            volumes:
              metabase_db:
            """
        ),
        ComposeStackTemplate(
            id: "odoo-postgres",
            title: "Odoo ERP + PostgreSQL",
            subtitle: "Odoo 18 business apps on port 8069",
            projectName: "odoo",
            yamlContent: """
            name: odoo

            services:
              db:
                image: docker.io/library/postgres:17-alpine
                container_name: odoo-db
                environment:
                  POSTGRES_USER: odoo
                  POSTGRES_PASSWORD: {{secret:db}}
                  POSTGRES_DB: postgres
                  PGDATA: /var/lib/postgresql/data/pgdata
                volumes:
                  - odoo_db:/var/lib/postgresql/data

              odoo:
                image: docker.io/library/odoo:18
                container_name: odoo-web
                ports:
                  - "8069:8069"
                environment:
                  HOST: db
                  USER: odoo
                  PASSWORD: {{secret:db}}
                depends_on:
                  - db

            volumes:
              odoo_db:
            """
        ),
        ComposeStackTemplate(
            id: "mediawiki-mariadb",
            title: "MediaWiki + MariaDB",
            subtitle: "A wiki on port 8097; finish setup in the browser (database host: db)",
            projectName: "mediawiki",
            yamlContent: """
            name: mediawiki

            services:
              db:
                image: docker.io/library/mariadb:11.8
                container_name: mediawiki-db
                command: --datadir=/var/lib/mysql/data
                environment:
                  MARIADB_ROOT_PASSWORD: {{secret:root}}
                  MARIADB_DATABASE: wiki
                  MARIADB_USER: wiki
                  MARIADB_PASSWORD: {{secret:db}}
                volumes:
                  - wiki_db:/var/lib/mysql

              mediawiki:
                image: docker.io/library/mediawiki:1.44
                container_name: mediawiki-web
                ports:
                  - "8097:80"
                depends_on:
                  - db

            volumes:
              wiki_db:
            """
        ),
        ComposeStackTemplate(
            id: "uptime-kuma",
            title: "Uptime Kuma monitoring",
            subtitle: "Status pages and uptime checks for your sites on port 3003",
            projectName: "uptime",
            yamlContent: """
            name: uptime

            services:
              kuma:
                image: docker.io/louislam/uptime-kuma:2
                container_name: uptime-kuma
                ports:
                  - "3003:3001"
                volumes:
                  - kuma_data:/app/data

            volumes:
              kuma_data:
            """
        ),
        ComposeStackTemplate(
            id: "rabbitmq",
            title: "RabbitMQ message broker",
            subtitle: "RabbitMQ on port 5672 with its management UI on port 15672",
            projectName: "rabbitmq",
            yamlContent: """
            name: rabbitmq

            services:
              rabbitmq:
                image: docker.io/library/rabbitmq:4-management-alpine
                container_name: rabbitmq
                ports:
                  - "5672:5672"
                  - "15672:15672"
                environment:
                  RABBITMQ_DEFAULT_USER: lada
                  RABBITMQ_DEFAULT_PASS: {{secret:rabbit}}
                volumes:
                  - rabbitmq_data:/var/lib/rabbitmq

            volumes:
              rabbitmq_data:
            """
        ),
        ComposeStackTemplate(
            id: "caddy-proxy",
            title: "Caddy reverse proxy + app",
            subtitle: "Caddy on port 8098 forwarding to a small web app (traefik/whoami)",
            projectName: "caddy-proxy",
            yamlContent: """
            name: caddy-proxy

            services:
              app:
                image: docker.io/traefik/whoami:v1.12.0
                container_name: caddy-app

              caddy:
                image: docker.io/library/caddy:2-alpine
                container_name: caddy-proxy
                command: caddy reverse-proxy --from :80 --to app:80
                ports:
                  - "8098:80"
                depends_on:
                  - app
            """
        )
    ]

    /// The template's YAML with each `{{secret:name}}` placeholder replaced by a fresh random value
    /// (the same name gets the same value, so services that share a password agree).
    public func instantiate() -> String {
        var result = yamlContent
        var values: [String: String] = [:]
        while let range = result.range(of: #"\{\{secret:([a-z0-9_]+)\}\}"#, options: .regularExpression) {
            let name = String(result[range].dropFirst(9).dropLast(2))
            let value = values[name] ?? SecretGenerator.password()
            values[name] = value
            result.replaceSubrange(range, with: value)
        }
        return result
    }
}

// MARK: - Compose YAML Parser

public enum ComposeParser {
    public static func isComposeFile(url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name == "docker-compose.yml"
            || name == "docker-compose.yaml"
            || name == "compose.yml"
            || name == "compose.yaml"
            || name.hasSuffix(".compose.yml")
            || name.hasSuffix(".compose.yaml")
    }

    public static func isComposeContent(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        return lines.contains {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return trimmed == "services:" || trimmed.hasPrefix("services:")
        }
    }

    public static func parse(yaml: String, defaultProjectName: String = "stack") -> ParsedComposeStack {
        var projectName = defaultProjectName
        var services: [ComposeServiceSpec] = []
        var declaredNetworks: [String] = []
        var declaredVolumes: [String] = []
        var warnings: [String] = []

        enum TopSection {
            case none
            case services
            case networks
            case volumes
        }

        enum ServiceSubsection {
            case none
            case ports
            case environment
            case volumes
            case dependsOn
            case networks
        }

        var topSection: TopSection = .none
        var currentService: ComposeServiceSpec? = nil
        var subSection: ServiceSubsection = .none
        var inNetworkAliases = false

        func flushCurrentService() {
            guard var svc = currentService else { return }
            if svc.imageReference.isEmpty {
                svc.imageReference = "docker.io/library/alpine:latest"
                warnings.append("Service '\(svc.serviceName)' had no 'image:' field; defaulted to alpine:latest.")
            } else if !svc.imageReference.contains("/") {
                svc.imageReference = "docker.io/library/\(svc.imageReference)"
            }
            // Apply Apple container ext4 compatibility defaults for Postgres/MySQL when mounted
            if svc.imageReference.lowercased().contains("postgres") {
                let hasPGData = svc.environment.contains { $0.key.uppercased() == "PGDATA" }
                if !hasPGData {
                    svc.environment.append(KeyValueEntry(key: "PGDATA", value: "/var/lib/postgresql/data/pgdata"))
                }
            }
            if svc.imageReference.lowercased().contains("mysql") && svc.commandOverride.isEmpty {
                svc.commandOverride = "--datadir=/var/lib/mysql/data"
            }
            services.append(svc)
            currentService = nil
        }

        let rawLines = yaml.components(separatedBy: .newlines)
        for rawLine in rawLines {
            let commentStripped: String = {
                if let hashIdx = rawLine.range(of: " #")?.lowerBound {
                    return String(rawLine[..<hashIdx])
                }
                return rawLine
            }()
            let trimmed = commentStripped.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed == "---" {
                continue
            }

            let indent = commentStripped.prefix(while: { $0 == " " || $0 == "\t" }).count

            // Top-level keys (indent == 0)
            if indent == 0 {
                flushCurrentService()
                subSection = .none
                if trimmed.hasPrefix("name:") {
                    let val = unquote(trimmed.dropFirst("name:".count))
                    if !val.isEmpty { projectName = sanitizeIdentifier(val) }
                    topSection = .none
                } else if trimmed == "services:" || trimmed.hasPrefix("services:") {
                    topSection = .services
                } else if trimmed == "networks:" || trimmed.hasPrefix("networks:") {
                    topSection = .networks
                } else if trimmed == "volumes:" || trimmed.hasPrefix("volumes:") {
                    topSection = .volumes
                } else {
                    topSection = .none
                }
                continue
            }

            switch topSection {
            case .networks:
                if indent <= 4, trimmed.hasSuffix(":") {
                    let netName = unquote(trimmed.dropLast())
                    if !netName.isEmpty && !declaredNetworks.contains(netName) {
                        declaredNetworks.append(netName)
                    }
                }
            case .volumes:
                if indent <= 4, trimmed.hasSuffix(":") {
                    let volName = unquote(trimmed.dropLast())
                    if !volName.isEmpty && !declaredVolumes.contains(volName) {
                        declaredVolumes.append(volName)
                    }
                }
            case .services:
                // Service header (typically indent == 2)
                if indent == 2 && trimmed.hasSuffix(":") && !trimmed.hasPrefix("-") {
                    flushCurrentService()
                    subSection = .none
                    let svcName = sanitizeIdentifier(unquote(trimmed.dropLast()))
                    currentService = ComposeServiceSpec(
                        serviceName: svcName,
                        containerName: "\(projectName)-\(svcName)",
                        imageReference: ""
                    )
                    continue
                }

                guard currentService != nil else { continue }

                // Service properties (typically indent == 4)
                if indent == 4 && !trimmed.hasPrefix("-") {
                    subSection = .none
                    inNetworkAliases = false
                    if let colonIndex = trimmed.firstIndex(of: ":") {
                        let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                        let val = unquote(trimmed[trimmed.index(after: colonIndex)...])

                        switch key {
                        case "image":
                            currentService?.imageReference = val
                        case "container_name":
                            if !val.isEmpty {
                                currentService?.containerName = sanitizeIdentifier(val)
                            }
                        case "build":
                            if !val.isEmpty {
                                currentService?.buildContext = val
                            }
                        case "command":
                            currentService?.commandOverride = val
                        case "mem_limit":
                            if let bytes = ByteSizeSpec.bytes(val.replacingOccurrences(of: "\"", with: "")), bytes > 0 {
                                currentService?.memoryLimitMB = Int(max(1, bytes / 1_048_576))
                            }
                        case "cpus":
                            if let cpus = Double(val.replacingOccurrences(of: "\"", with: "")), cpus > 0 {
                                currentService?.cpuLimit = Int(cpus.rounded(.up))
                            }
                        case "working_dir":
                            currentService?.workingDirectory = val
                        case "ports":
                            subSection = .ports
                        case "environment":
                            subSection = .environment
                        case "volumes":
                            subSection = .volumes
                        case "depends_on":
                            subSection = .dependsOn
                        case "networks":
                            subSection = .networks
                        default:
                            break
                        }
                    }
                    continue
                }

                // Subsection items (indent >= 4)
                switch subSection {
                case .ports:
                    if trimmed.hasPrefix("-") {
                        let spec = unquote(trimmed.dropFirst())
                        if let pm = parsePortSpec(spec) {
                            currentService?.publishedPorts.append(pm)
                        }
                    }
                case .environment:
                    if trimmed.hasPrefix("-") {
                        let item = unquote(trimmed.dropFirst())
                        if let eq = item.firstIndex(of: "=") {
                            let k = String(item[..<eq]).trimmingCharacters(in: .whitespaces)
                            let v = unquote(item[item.index(after: eq)...])
                            currentService?.environment.append(KeyValueEntry(key: k, value: v, isSecret: SecretRedactor.isSensitiveKey(k)))
                        }
                    } else if let colon = trimmed.firstIndex(of: ":") {
                        let k = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                        let v = unquote(trimmed[trimmed.index(after: colon)...])
                        currentService?.environment.append(KeyValueEntry(key: k, value: v, isSecret: SecretRedactor.isSensitiveKey(k)))
                    }
                case .volumes:
                    if trimmed.hasPrefix("-") {
                        let spec = unquote(trimmed.dropFirst())
                        if let mount = parseVolumeSpec(spec, projectName: projectName) {
                            currentService?.volumes.append(mount)
                            if mount.kind == .volume && !declaredVolumes.contains(mount.source) {
                                declaredVolumes.append(mount.source)
                            }
                        }
                    }
                case .dependsOn:
                    if trimmed.hasPrefix("-") {
                        let dep = sanitizeIdentifier(unquote(trimmed.dropFirst()))
                        if !dep.isEmpty {
                            currentService?.dependsOn.append(dep)
                        }
                    } else if indent == 6 && trimmed.hasSuffix(":") {
                        let dep = sanitizeIdentifier(unquote(trimmed.dropLast()))
                        if !dep.isEmpty {
                            currentService?.dependsOn.append(dep)
                        }
                    }
                case .networks:
                    if inNetworkAliases && indent >= 10 && trimmed.hasPrefix("-") {
                        // networks: <name>: aliases: - <alias>
                        let alias = unquote(trimmed.dropFirst()).lowercased()
                        if !alias.isEmpty { currentService?.networkAliases.append(alias) }
                    } else if trimmed.hasPrefix("-") {
                        let net = sanitizeIdentifier(unquote(trimmed.dropFirst()))
                        if !net.isEmpty {
                            currentService?.networks.append(net)
                        }
                    } else if indent == 6, trimmed.hasSuffix(":") || trimmed.contains(": ") {
                        // Mapping form: `backend:` or `backend: {}`
                        inNetworkAliases = false
                        let name = String(trimmed[..<(trimmed.firstIndex(of: ":") ?? trimmed.endIndex)])
                        let net = sanitizeIdentifier(unquote(name))
                        if !net.isEmpty, currentService?.networks.contains(net) == false {
                            currentService?.networks.append(net)
                        }
                    } else if indent >= 8, trimmed.hasPrefix("aliases:") {
                        let rest = unquote(trimmed.dropFirst("aliases:".count))
                        if rest.hasPrefix("[") && rest.hasSuffix("]") {
                            // Flow form: aliases: [db, database]
                            inNetworkAliases = false
                            for item in rest.dropFirst().dropLast().split(separator: ",") {
                                let alias = unquote(item).lowercased()
                                if !alias.isEmpty { currentService?.networkAliases.append(alias) }
                            }
                        } else {
                            inNetworkAliases = true
                        }
                    } else if indent >= 8 {
                        inNetworkAliases = false
                    }
                case .none:
                    break
                }
            case .none:
                break
            }
        }

        flushCurrentService()
        return ParsedComposeStack(
            projectName: projectName,
            services: services,
            declaredNetworks: declaredNetworks,
            declaredVolumes: declaredVolumes,
            warnings: warnings
        )
    }

    /// DNS aliases for a service so its peers can reach it by service name (container 1.6+).
    ///
    /// Candidates are the service name plus any `aliases:` from the Compose file. Upstream accepts a
    /// single-label alias such as `db` only when a default DNS domain is configured (it then
    /// appends the domain); aliases must also be unique across containers. Candidates that would
    /// make the create fail are skipped with a note instead.
    ///
    /// - Parameters:
    ///   - defaultDNSDomain: the runtime's `dns.domain` property, if any.
    ///   - claimedNames: canonical names (lowercase, fully qualified, no trailing dot) already used
    ///     as aliases by other containers on the network.
    public static func serviceDNSAliases(
        for service: ComposeServiceSpec,
        defaultDNSDomain: String?,
        claimedNames: Set<String>
    ) -> (aliases: [String], notes: [String]) {
        let domain = defaultDNSDomain?.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
        var aliases: [String] = []
        var notes: [String] = []
        var seen = Set<String>()
        for candidate in [service.serviceName] + service.networkAliases {
            let alias = candidate.lowercased()
            guard ValidationUtils.isValidDNSAlias(alias) else {
                notes.append("Skipped invalid DNS alias '\(alias)'.")
                continue
            }
            let isSubtree = alias.hasPrefix(".")
            let singleLabel = ValidationUtils.dnsLabelCount(alias) < 2
            if singleLabel && (domain ?? "").isEmpty {
                notes.append("'\(alias)' is not resolvable by name: set a default DNS domain (`container system dns create test`, then `container system property set dns.domain test`) or use a name like '\(alias).test'.")
                continue
            }
            var canonical = alias.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if singleLabel, let domain, !domain.isEmpty { canonical += ".\(domain)" }
            guard !isSubtree || !singleLabel else { continue }
            guard seen.insert((isSubtree ? "." : "") + canonical).inserted else { continue }
            if !isSubtree && claimedNames.contains(canonical) {
                notes.append("Skipped DNS alias '\(alias)': already used by another container.")
                continue
            }
            aliases.append(alias)
        }
        return (Array(aliases.prefix(ValidationUtils.maximumDNSAliasesPerNetwork)), notes)
    }

    /// Canonical alias names (see `serviceDNSAliases`) used by `containers`, for conflict checks.
    public static func claimedDNSNames(in containers: [ContainerModel], network: String, defaultDNSDomain: String?, excluding excludedID: String) -> Set<String> {
        let domain = defaultDNSDomain?.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased() ?? ""
        var names = Set<String>()
        for c in containers where c.id != excludedID {
            for alias in c.configuration.networkAliases[network] ?? [] {
                var canonical = alias.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if ValidationUtils.dnsLabelCount(canonical) < 2 && !domain.isEmpty { canonical += ".\(domain)" }
                names.insert(canonical)
            }
        }
        return names
    }

    public static func buildContainerRequest(
        for service: ComposeServiceSpec,
        projectName: String,
        networkName: String,
        defaultCPUs: Int,
        defaultMemoryMB: Int,
        dnsAliases: [String] = []
    ) -> ContainerCreateRequest {
        // Compose semantics: `command:` replaces the image's CMD and keeps its ENTRYPOINT, so
        // entrypoint scripts (database init, config templating) still run. Strings are split
        // like a shell does (quotes group words); the list form is taken as is.
        let cmdArgs = ShellWords.composeCommand(service.commandOverride)
        let entryOverride = ""

        return ContainerCreateRequest(
            name: service.containerName,
            imageReference: service.imageReference,
            startImmediately: true,
            entrypointOverride: entryOverride,
            commandArguments: cmdArgs,
            workingDirectory: service.workingDirectory,
            publishedPorts: service.publishedPorts,
            networkName: networkName,
            dnsAliases: dnsAliases,
            mounts: service.volumes,
            environmentVariables: service.environment,
            cpus: service.cpuLimit ?? defaultCPUs,
            memoryMB: service.memoryLimitMB ?? defaultMemoryMB,
            labels: [
                KeyValueEntry(key: "com.lada.compose.project", value: projectName),
                KeyValueEntry(key: "com.lada.compose.service", value: service.serviceName)
            ]
        )
    }

    private static func parsePortSpec(_ raw: String) -> PortMapping? {
        var proto = "tcp"
        var cleaned = raw
        if cleaned.lowercased().hasSuffix("/udp") {
            proto = "udp"
            cleaned = String(cleaned.dropLast(4))
        } else if cleaned.lowercased().hasSuffix("/tcp") {
            proto = "tcp"
            cleaned = String(cleaned.dropLast(4))
        }
        let segments = cleaned.split(separator: ":").map(String.init)
        if segments.count == 2,
           let hostPort = UInt16(segments[0]),
           let containerPort = UInt16(segments[1]) {
            return PortMapping(hostAddress: "127.0.0.1", hostPort: hostPort, containerPort: containerPort, proto: proto)
        } else if segments.count == 3,
                  let hostPort = UInt16(segments[1]),
                  let containerPort = UInt16(segments[2]) {
            return PortMapping(hostAddress: segments[0], hostPort: hostPort, containerPort: containerPort, proto: proto)
        } else if segments.count == 1,
                  let port = UInt16(segments[0]) {
            return PortMapping(hostAddress: "127.0.0.1", hostPort: port, containerPort: port, proto: proto)
        }
        return nil
    }

    private static func parseVolumeSpec(_ raw: String, projectName: String) -> MountAttachment? {
        let parts = raw.split(separator: ":").map(String.init)
        guard parts.count >= 2 else { return nil }
        let src = parts[0]
        let dst = parts[1]
        let ro = parts.count >= 3 && parts[2].lowercased().contains("ro")
        if src.hasPrefix("/") || src.hasPrefix("./") || src.hasPrefix("../") || src.hasPrefix("~") {
            let expanded = (src as NSString).expandingTildeInPath
            return MountAttachment(kind: .bind, source: expanded, destination: dst, readOnly: ro)
        } else {
            return MountAttachment(kind: .volume, source: src, destination: dst, readOnly: ro, volumeName: src)
        }
    }

    private static func unquote<S: StringProtocol>(_ s: S) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
            if t.count >= 2 {
                t.removeFirst()
                t.removeLast()
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizeIdentifier(_ raw: String) -> String {
        let allowed = raw.lowercased().map { ch -> Character in
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == "." {
                return ch
            }
            return "-"
        }
        let cleaned = String(allowed).trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
        if cleaned.count < 2 {
            return cleaned.isEmpty ? "stack-svc" : "\(cleaned)01"
        }
        return cleaned
    }
}


/// Splits command strings the way Compose (and a POSIX shell) does, without running a shell.
public enum ShellWords {
    /// `sh -c "echo hi && run"` → ["sh", "-c", "echo hi && run"]. Single quotes are literal,
    /// double quotes allow `\"` and `\\`, a backslash outside quotes escapes the next character.
    public static func split(_ input: String) -> [String] {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quote: Character?
        var escaping = false
        for ch in input {
            if escaping {
                current.append(ch); escaping = false; inWord = true; continue
            }
            switch quote {
            case "'":
                if ch == "'" { quote = nil } else { current.append(ch) }
            case "\"":
                if ch == "\"" { quote = nil } else if ch == "\\" { escaping = true } else { current.append(ch) }
            default:
                if ch == "\\" { escaping = true; inWord = true }
                else if ch == "'" || ch == "\"" { quote = ch; inWord = true }
                else if ch == " " || ch == "\t" || ch == "\n" {
                    if inWord { words.append(current); current = ""; inWord = false }
                } else { current.append(ch); inWord = true }
            }
        }
        if inWord { words.append(current) }
        return words
    }

    /// A Compose `command:` value: the flow-list form `["a", "b c"]` or a shell-style string.
    public static func composeCommand(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]"),
           let data = trimmed.data(using: .utf8),
           let list = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return list
        }
        return split(trimmed)
    }
}
