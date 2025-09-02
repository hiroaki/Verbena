# Verbena Mail Queue Service

**ALWAYS** follow these instructions first. Only fallback to additional search or bash commands when the information here is incomplete or found to be in error.

Verbena is a Ruby on Rails 7.1 EML-based mail queue and SMTP delivery service with a REST API for mail input and processing. The application uses Docker for development with MySQL/MariaDB database.

## Working Effectively

### Prerequisites and Setup
- Install Docker and Docker Compose on your system
- Ensure you have at least 2GB free disk space for Docker images
- **CRITICAL**: Network access to rubygems.org and Docker Hub is required for builds

**Local Development Alternative (if Docker unavailable):**
- Ruby 3.2.0 (exact version required due to Gemfile.lock)
- MySQL or MariaDB server running locally
- Access to install gems via bundler
- **Note**: Local setup requires significant environment configuration and is not recommended

**Hard Dependencies:**
- Internet access to rubygems.org for gem installation
- Docker Hub access for base image downloads
- MySQL/MariaDB database (either via Docker or local installation)

### Bootstrap and Build Process
```bash
# Clone and setup environment
git clone https://github.com/hiroaki/Verbena.git
cd Verbena
git checkout develop
cp dot.env.sample .env

# Build Docker images - NEVER CANCEL: Takes 3-5 minutes depending on network
docker compose build
# Set timeout to 10+ minutes for this command

# Start services - Database initialization takes 30-60 seconds  
docker compose up -d

# Create and migrate database - NEVER CANCEL: Takes 2-3 minutes
docker compose exec web rails db:migrate:reset
# Set timeout to 5+ minutes for this command
```

### Testing
```bash
# Run complete test suite - NEVER CANCEL: Takes 3-5 minutes to complete
docker compose exec web bin/rspec
# Set timeout to 10+ minutes for this command

# Run specific tests faster
docker compose exec web bin/rspec spec/models/
docker compose exec web bin/rspec spec/services/

# Run with coverage (generates coverage report)
docker compose exec web DISABLE_SPRING=1 bin/rspec
```

### Running the Application
```bash
# Start web server (development mode)
docker compose exec web bundle exec rails server -b 0.0.0.0

# Access the application
# Web UI: http://localhost:23000
# API: http://localhost:23000/api/v1/mail_queues
# Database: localhost:23306 (user: railsuser, password: railspass)

# Open Rails console for debugging
docker compose exec web bundle exec rails console

# Check logs
docker compose logs web
docker compose logs db
```

## Validation Scenarios

**ALWAYS** run these validation scenarios after making changes to ensure the application works correctly:

### 1. Database and Model Validation
```bash
# Verify database connectivity and tables
docker compose exec web rails runner "puts MailQueue.count"
docker compose exec web rails runner "puts Token.count"

# Test model creation
docker compose exec web rails runner "
token = Token.create!(label: 'test', key: 'test123')
puts 'Token created: ' + token.id.to_s
"
```

### 2. Mail Queue API Validation
```bash
# Create a test token for API access
docker compose exec web rails runner "Token.create!(label: 'test', key: 'secret')"

# Test API endpoint (requires test EML file)
# Create test EML file first:
cat > /tmp/test.eml << 'EOF'
Date: Tue, 1 Jul 2003 10:52:37 +0200
From: test@example.com
To: recipient@example.com
Subject: Test Email
Content-Type: text/plain; charset="UTF-8"

This is a test email.
EOF

# Copy to container and test API
docker cp /tmp/test.eml verbena-web-1:/tmp/test.eml
docker compose exec web curl -H 'Authorization: Bearer secret' -X POST \
  -F 'mail_queue[eml]=@/tmp/test.eml' \
  http://localhost:3000/api/v1/mail_queues

# Verify mail queue was created
docker compose exec web rails runner "puts MailQueue.count"
```

### 3. Mail Delivery Validation
```bash
# Test mail delivery by timer (test mode - no actual SMTP)
docker compose exec web bin/rails verbena:delivery:by_timer

# Check delivery responses
docker compose exec web rails runner "puts DeliveryResponse.count"

# Test cleanup functionality
docker compose exec web bin/rails verbena:cleanup:now[true]  # dry run
```

## Configuration and Environment

### Environment Variables (ENV-first Pattern)
- Copy `dot.env.sample` to `.env` and modify as needed
- **NEVER** commit credentials or secrets to source code
- Use `VERBENA_DELIVERY_METHOD=test` for development (default)
- Set `VERBENA_DELIVERY_METHOD=smtp` only in production with proper SMTP credentials

### Key Environment Variables:
```bash
# Delivery settings
VERBENA_DELIVERY_METHOD=test|smtp|file  # Use 'test' for development
VERBENA_FILE_DELIVERY_DIR=tmp/mails     # For file delivery mode

# SMTP settings (required only when VERBENA_DELIVERY_METHOD=smtp)
VERBENA_DELIVERY_SMTP_ADDRESS=localhost
VERBENA_DELIVERY_SMTP_PORT=1025
VERBENA_DELIVERY_SMTP_DOMAIN=localhost
VERBENA_DELIVERY_SMTP_USER_NAME=
VERBENA_DELIVERY_SMTP_PASSWORD=
VERBENA_DELIVERY_SMTP_AUTHENTICATION=plain

# General settings
VERBENA_EML_MAX_BYTES=10485760          # 10MB default
VERBENA_CLEANUP_TTL_DAYS=30             # Cleanup retention period
```

## Common Commands and Timing

### Essential Commands (Verified)
| Command | Purpose | Timeout | Notes |
|---------|---------|---------|-------|
| `docker compose build` | Build containers | 10+ min | **REQUIRES** internet access |
| `docker compose up -d` | Start services | 2 min | Database needs 60s to initialize |
| `docker compose exec web rails db:migrate:reset` | Setup database | 5+ min | **NEVER CANCEL** |
| `docker compose exec web bin/rspec` | Run test suite | 10+ min | **NEVER CANCEL** |
| `docker compose exec web rails console` | Debug console | 1 min | For interactive debugging |

### Rake Tasks (all require environment setup)
```bash
# Mail queue management
docker compose exec web bin/rails verbena:mail_queues:add[/path/to/file.eml]
docker compose exec web bin/rails verbena:mail_queues:delete[queue_id]

# Mail delivery
docker compose exec web bin/rails verbena:delivery:by_timer      # Process scheduled mails
docker compose exec web bin/rails verbena:delivery:by_ids[1,2,3] # Process specific IDs

# Cleanup (maintenance)
docker compose exec web bin/rails verbena:cleanup:weekly[true]   # Dry run
docker compose exec web bin/rails verbena:cleanup:weekly         # Execute
docker compose exec web bin/rails verbena:cleanup:by_ttl        # Use TTL setting
```

### Performance and Timing Expectations
- **Database migration**: 2-3 minutes - NEVER CANCEL, set timeout 5+ minutes
- **Docker build**: 2-5 minutes (measured: 2+ minutes before network failure) - NEVER CANCEL, set timeout 10+ minutes  
- **Test suite**: 3-5 minutes - NEVER CANCEL, set timeout 10+ minutes
- **Rails console startup**: 30-60 seconds
- **API responses**: < 1 second for single operations
- **Mail delivery processing**: 1-10 seconds per message depending on SMTP

**Measured Build Times:**
- Docker image pull and base setup: ~60 seconds
- Bundle install (when network available): 3-5 minutes depending on gems
- Total expected build time: 5-8 minutes on first build

## Development Patterns and Best Practices

### Code Organization
- **Services**: Business logic in `app/services/verbena/` namespace
- **Models**: `MailQueue`, `EmlSource`, `DeliveryResponse`, `Token`
- **API**: RESTful endpoints under `/api/v1/` namespace
- **Rake Tasks**: Domain-specific tasks in `lib/tasks/verbena/`

### Testing Guidelines
- Use RSpec for all tests with factories (FactoryBot)
- Run `bin/rspec` to execute test suite
- Coverage reports generated by SimpleCov
- Disable Spring for accurate coverage: `DISABLE_SPRING=1 bin/rspec`
- **ALWAYS** run tests before committing changes

### Database Patterns
- MySQL/MariaDB as primary database
- Migration-driven schema changes
- Envelope-based mail addressing (separate from EML headers)
- Soft deletion pattern for cleanup operations

## Troubleshooting

### Docker Issues
```bash
# Rebuild containers if gems change
docker compose down
docker compose build --no-cache
docker compose up -d

# Clear Docker volumes if database issues
docker compose down -v
docker compose up -d
docker compose exec web rails db:migrate:reset

# Check container status
docker compose ps
docker compose logs web
```

### When Docker Build Fails (Network/Environment Issues)
If you encounter build failures in restricted environments:

1. **Expected Failure Pattern:**
   ```
   Could not fetch specs from https://rubygems.org/ due to underlying error
   <SocketError: Failed to open TCP connection to rubygems.org:443>
   ```

2. **Required Actions:**
   - **DO NOT** attempt workarounds or modifications to Dockerfile
   - **Document the failure** in your work rather than trying to fix environment limitations
   - **Inform users** that full internet access is required for development
   - **Note**: This is a hard requirement, not a configuration issue

3. **Alternative Validation (when full Docker setup fails):**
   ```bash
   # Verify file structure and configuration
   cat compose.yml | grep "23000\|23306"  # Check port mappings
   cat dot.env.sample | head -10           # Verify environment template
   ls -la app/services/verbena/            # Check service organization
   grep -r "mail_queues" config/routes.rb  # Verify API endpoints
   ```

### Network/Connectivity Issues
- Docker build failures usually indicate network connectivity problems
- If `docker compose build` fails with DNS/connection errors, verify internet access
- RubyGems.org access required for bundle install during build
- Consider using cached Docker images or offline gem sources in restricted environments

**IMPORTANT**: In sandboxed or restricted network environments:
- `docker compose build` WILL FAIL due to network restrictions
- `bundle install` requires internet access to rubygems.org
- Document the failure in your instructions rather than providing workarounds
- Inform users that network access is a hard requirement for development
- Example failure: "Could not fetch specs from https://rubygems.org/ due to underlying error"

### Common Error Solutions
- **"Could not fetch specs from rubygems.org"**: Network connectivity issue during build
- **"Access denied for user"**: Database container not fully started, wait 60 seconds and retry
- **"Rails server already running"**: Remove `tmp/pids/server.pid` file
- **Test failures**: Check test database with `RAILS_ENV=test rails db:migrate:reset`

## Repository Structure Reference

```
/
├── app/
│   ├── controllers/api/v1/     # REST API endpoints
│   ├── models/                 # MailQueue, Token, EmlSource, DeliveryResponse
│   └── services/verbena/       # Business logic services
├── config/
│   ├── database.yml           # Database configuration
│   └── initializers/verbena_env.rb  # Environment configuration
├── lib/tasks/verbena/         # Domain-specific rake tasks
├── spec/                      # RSpec test suite
├── compose.yml                # Docker development setup
├── Dockerfile                 # Container definition
├── dot.env.sample            # Environment template
└── README.md                 # Japanese documentation
```

### Key Files to Monitor
- **Always check `config/initializers/verbena_env.rb`** after modifying environment variables
- **Review `app/services/verbena/` classes** when changing business logic
- **Update corresponding specs in `spec/services/`** when modifying services
- **Check `lib/tasks/verbena/` files** when adding new rake tasks