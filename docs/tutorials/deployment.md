---
layout: tutorial
title: Production Deployment
description: Complete guide to deploying RCrewAI applications in production with Docker, Kubernetes, monitoring, and enterprise features
---

# Production Deployment

This comprehensive tutorial covers deploying RCrewAI applications to production environments with enterprise-grade reliability, monitoring, scaling, and security. You'll learn containerization, orchestration, monitoring, and operational best practices.

## Table of Contents
1. [Production Readiness Checklist](#production-readiness-checklist)
2. [Containerization with Docker](#containerization-with-docker)
3. [Kubernetes Deployment](#kubernetes-deployment)
4. [Configuration Management](#configuration-management)
5. [Monitoring and Observability](#monitoring-and-observability)
6. [Scaling and Load Balancing](#scaling-and-load-balancing)
7. [Security and Access Control](#security-and-access-control)
8. [CI/CD Pipeline](#cicd-pipeline)
9. [Operational Procedures](#operational-procedures)
10. [Troubleshooting and Recovery](#troubleshooting-and-recovery)

## Production Readiness Checklist

Before deploying to production, ensure your RCrewAI application meets these requirements:

### ✅ Code Quality
- [ ] Comprehensive test coverage (>90%)
- [ ] Code review process in place
- [ ] Static analysis and linting
- [ ] Performance benchmarks established
- [ ] Security vulnerability scanning

### ✅ Configuration
- [ ] Environment-based configuration
- [ ] Secrets management implemented
- [ ] Resource limits defined
- [ ] Timeout and retry logic configured
- [ ] Logging levels appropriate for production

### ✅ Monitoring
- [ ] Health check endpoints implemented
- [ ] Metrics collection configured
- [ ] Alerting rules defined
- [ ] Log aggregation setup
- [ ] Performance monitoring enabled

### ✅ Infrastructure
- [ ] Load balancing configured
- [ ] Auto-scaling policies defined
- [ ] Backup and disaster recovery plan
- [ ] Network security implemented
- [ ] Resource quotas established

## Containerization with Docker

### Basic Dockerfile

```dockerfile
# Use official Ruby runtime as base image
FROM ruby:3.1-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy Gemfile and Gemfile.lock
COPY Gemfile Gemfile.lock ./

# Install Ruby dependencies
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install

# Copy application code
COPY . .

# Create non-root user for security
RUN groupadd -r rcrewai && useradd -r -g rcrewai rcrewai
RUN chown -R rcrewai:rcrewai /app
USER rcrewai

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Default command
CMD ["ruby", "production_app.rb"]
```

### Multi-stage Production Dockerfile

```dockerfile
# Build stage
FROM ruby:3.1-slim AS builder

RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install

# Production stage
FROM ruby:3.1-slim AS production

# Install only runtime dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get autoremove -y

WORKDIR /app

# Copy gems from builder stage
COPY --from=builder /usr/local/bundle /usr/local/bundle

# Copy application code
COPY . .

# Create non-root user
RUN groupadd -r rcrewai && useradd -r -g rcrewai -d /app rcrewai
RUN chown -R rcrewai:rcrewai /app

# Switch to non-root user
USER rcrewai

# Environment variables
ENV RAILS_ENV=production
ENV RACK_ENV=production
ENV BUNDLE_DEPLOYMENT=true
ENV BUNDLE_WITHOUT="development:test"

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD ruby health_check.rb || exit 1

EXPOSE 8080

CMD ["ruby", "production_app.rb"]
```

### Production Application Structure

```ruby
# production_app.rb
require 'rcrewai'
require 'sinatra'
require 'json'
require 'logger'
require 'prometheus/middleware/collector'
require 'prometheus/middleware/exporter'

class ProductionRCrewAI < Sinatra::Base
  configure :production do
    enable :logging
    set :logger, Logger.new($stdout)
    
    # Metrics collection
    use Prometheus::Middleware::Collector
    use Prometheus::Middleware::Exporter
    
    # Configure RCrewAI for production
    RCrewAI.configure do |config|
      config.llm_provider = ENV.fetch('LLM_PROVIDER', 'openai').to_sym
      config.openai_api_key = ENV.fetch('OPENAI_API_KEY')
      config.temperature = ENV.fetch('LLM_TEMPERATURE', '0.1').to_f
      config.max_tokens = ENV.fetch('LLM_MAX_TOKENS', '4000').to_i
      config.timeout = ENV.fetch('LLM_TIMEOUT', '60').to_i
    end
    
    # Initialize crew registry
    @@crew_registry = CrewRegistry.new
    @@crew_registry.register_default_crews
  end
  
  # Health check endpoint
  get '/health' do
    content_type :json
    
    begin
      health_status = perform_health_check
      status health_status[:status] == 'healthy' ? 200 : 503
      health_status.to_json
    rescue => e
      status 503
      { status: 'unhealthy', error: e.message }.to_json
    end
  end
  
  # Readiness check endpoint
  get '/ready' do
    content_type :json
    
    begin
      readiness_status = perform_readiness_check
      status readiness_status[:ready] ? 200 : 503
      readiness_status.to_json
    rescue => e
      status 503
      { ready: false, error: e.message }.to_json
    end
  end
  
  # Metrics endpoint
  get '/metrics' do
    # Prometheus metrics are handled by middleware
  end
  
  # Main execution endpoint
  post '/execute' do
    content_type :json
    
    begin
      request_data = JSON.parse(request.body.read)
      
      # Validate request
      validate_execution_request(request_data)
      
      # Get crew
      crew_name = request_data['crew_name']
      crew = @@crew_registry.get_crew(crew_name)
      
      # Execute with monitoring
      result = execute_with_monitoring(crew, request_data)
      
      status 200
      result.to_json
      
    rescue JSON::ParserError
      status 400
      { error: 'Invalid JSON in request body' }.to_json
    rescue ValidationError => e
      status 400
      { error: e.message }.to_json
    rescue => e
      logger.error "Execution failed: #{e.message}"
      logger.error e.backtrace.join("\n")
      
      status 500
      { error: 'Internal server error' }.to_json
    end
  end
  
  private
  
  def perform_health_check
    checks = {
      timestamp: Time.now.iso8601,
      status: 'healthy',
      checks: {}
    }
    
    # Check LLM provider connectivity
    begin
      # Quick LLM test
      RCrewAI.client.chat(
        messages: [{ role: 'user', content: 'test' }],
        max_tokens: 1,
        temperature: 0
      )
      checks[:checks][:llm] = { status: 'healthy' }
    rescue => e
      checks[:checks][:llm] = { status: 'unhealthy', error: e.message }
      checks[:status] = 'unhealthy'
    end
    
    # Check memory usage
    memory_usage = get_memory_usage
    if memory_usage > 0.9
      checks[:checks][:memory] = { status: 'warning', usage: memory_usage }
      checks[:status] = 'degraded'
    else
      checks[:checks][:memory] = { status: 'healthy', usage: memory_usage }
    end
    
    checks
  end
  
  def perform_readiness_check
    {
      ready: true,
      timestamp: Time.now.iso8601,
      crews: @@crew_registry.crew_count,
      uptime: Process.clock_gettime(Process::CLOCK_MONOTONIC).to_i
    }
  end
  
  def validate_execution_request(data)
    required_fields = ['crew_name']
    missing_fields = required_fields - data.keys
    
    if missing_fields.any?
      raise ValidationError, "Missing required fields: #{missing_fields.join(', ')}"
    end
    
    unless @@crew_registry.crew_exists?(data['crew_name'])
      raise ValidationError, "Unknown crew: #{data['crew_name']}"
    end
  end
  
  def execute_with_monitoring(crew, request_data)
    start_time = Time.now
    execution_id = SecureRandom.uuid
    
    logger.info "Starting execution", {
      execution_id: execution_id,
      crew_name: crew.name,
      request_id: request_data['request_id']
    }
    
    begin
      # Execute crew
      result = crew.execute(
        timeout: ENV.fetch('EXECUTION_TIMEOUT', '300').to_i,
        max_retries: ENV.fetch('MAX_RETRIES', '3').to_i
      )
      
      duration = Time.now - start_time
      
      logger.info "Execution completed", {
        execution_id: execution_id,
        duration: duration,
        success_rate: result[:success_rate]
      }
      
      {
        execution_id: execution_id,
        success: true,
        duration: duration,
        result: result
      }
      
    rescue => e
      duration = Time.now - start_time
      
      logger.error "Execution failed", {
        execution_id: execution_id,
        duration: duration,
        error: e.message
      }
      
      raise
    end
  end
  
  def get_memory_usage
    # Simple memory usage check
    memory_info = `cat /proc/meminfo`.split("\n")
    total = memory_info.find { |line| line.start_with?('MemTotal:') }.split[1].to_i
    available = memory_info.find { |line| line.start_with?('MemAvailable:') }.split[1].to_i
    
    (total - available).to_f / total
  rescue
    0.0
  end
end

class ValidationError < StandardError; end

class CrewRegistry
  def initialize
    @crews = {}
  end
  
  def register_crew(name, crew)
    @crews[name] = crew
  end
  
  def get_crew(name)
    crew = @crews[name]
    raise ValidationError, "Crew not found: #{name}" unless crew
    crew
  end
  
  def crew_exists?(name)
    @crews.key?(name)
  end
  
  def crew_count
    @crews.length
  end
  
  def register_default_crews
    # Register your production crews here
    support_crew = create_support_crew
    register_crew('customer_support', support_crew)
    
    analysis_crew = create_analysis_crew  
    register_crew('data_analysis', analysis_crew)
  end
  
  private
  
  def create_support_crew
    crew = RCrewAI::Crew.new("customer_support")
    
    support_agent = RCrewAI::Agent.new(
      name: "support_specialist",
      role: "Customer Support Specialist",
      goal: "Provide excellent customer support and resolve issues efficiently",
      tools: [
        RCrewAI::Tools::WebSearch.new(max_results: 5),
        RCrewAI::Tools::FileReader.new
      ]
    )
    
    crew.add_agent(support_agent)
    
    support_task = RCrewAI::Task.new(
      name: "handle_support_request",
      description: "Handle customer support request with empathy and expertise",
      expected_output: "Professional support response with clear next steps"
    )
    
    crew.add_task(support_task)
    crew
  end
  
  def create_analysis_crew
    crew = RCrewAI::Crew.new("data_analysis")
    
    analyst = RCrewAI::Agent.new(
      name: "data_analyst",
      role: "Senior Data Analyst", 
      goal: "Analyze data and provide actionable insights",
      tools: [
        RCrewAI::Tools::FileReader.new,
        RCrewAI::Tools::WebSearch.new
      ]
    )
    
    crew.add_agent(analyst)
    
    analysis_task = RCrewAI::Task.new(
      name: "data_analysis",
      description: "Perform comprehensive data analysis and generate insights",
      expected_output: "Detailed analysis report with charts and recommendations"
    )
    
    crew.add_task(analysis_task)
    crew
  end
end

# Health check script for Docker
# health_check.rb
begin
  require 'net/http'
  
  uri = URI('http://localhost:8080/health')
  response = Net::HTTP.get_response(uri)
  
  exit(response.code == '200' ? 0 : 1)
rescue
  exit 1
end

# Start the application
if __FILE__ == $0
  ProductionRCrewAI.run!(
    host: '0.0.0.0',
    port: ENV.fetch('PORT', 8080).to_i
  )
end
```

### Docker Compose for Development

```yaml
# docker-compose.yml
version: '3.8'

services:
  rcrewai:
    build:
      context: .
      dockerfile: Dockerfile
      target: production
    ports:
      - "8080:8080"
    environment:
      - RAILS_ENV=production
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - LLM_PROVIDER=openai
      - LLM_TEMPERATURE=0.1
      - EXECUTION_TIMEOUT=300
      - MAX_RETRIES=3
    depends_on:
      - redis
      - prometheus
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "ruby", "health_check.rb"]
      interval: 30s
      timeout: 10s
      retries: 3
    
  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    restart: unless-stopped
    
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
    restart: unless-stopped
    
  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/dashboards:/etc/grafana/provisioning/dashboards
      - ./grafana/datasources:/etc/grafana/provisioning/datasources
    restart: unless-stopped

volumes:
  redis_data:
  prometheus_data:
  grafana_data:
```

## Kubernetes Deployment

### Deployment Configuration

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rcrewai-app
  labels:
    app: rcrewai
    version: v1.0.0
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
  selector:
    matchLabels:
      app: rcrewai
  template:
    metadata:
      labels:
        app: rcrewai
        version: v1.0.0
    spec:
      serviceAccountName: rcrewai-service-account
      containers:
      - name: rcrewai
        image: your-registry/rcrewai:v1.0.0
        ports:
        - containerPort: 8080
        env:
        - name: RAILS_ENV
          value: "production"
        - name: OPENAI_API_KEY
          valueFrom:
            secretKeyRef:
              name: rcrewai-secrets
              key: openai-api-key
        - name: REDIS_URL
          value: "redis://redis-service:6379"
        - name: LLM_PROVIDER
          value: "openai"
        - name: LLM_TEMPERATURE
          value: "0.1"
        - name: EXECUTION_TIMEOUT
          value: "300"
        - name: MAX_RETRIES
          value: "3"
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 30
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          readOnlyRootFilesystem: true
          allowPrivilegeEscalation: false
        volumeMounts:
        - name: tmp-volume
          mountPath: /tmp
      volumes:
      - name: tmp-volume
        emptyDir: {}
      imagePullSecrets:
      - name: registry-secret
---
apiVersion: v1
kind: Service
metadata:
  name: rcrewai-service
  labels:
    app: rcrewai
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
    name: http
  selector:
    app: rcrewai
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: rcrewai-service-account
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rcrewai-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/rate-limit: "100"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
  - hosts:
    - api.yourcompany.com
    secretName: rcrewai-tls
  rules:
  - host: api.yourcompany.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: rcrewai-service
            port:
              number: 80
```

### ConfigMap and Secrets

```yaml
# k8s/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: rcrewai-config
data:
  LLM_PROVIDER: "openai"
  LLM_TEMPERATURE: "0.1"
  LLM_MAX_TOKENS: "4000"
  EXECUTION_TIMEOUT: "300"
  MAX_RETRIES: "3"
  LOG_LEVEL: "INFO"
  METRICS_ENABLED: "true"
---
apiVersion: v1
kind: Secret
metadata:
  name: rcrewai-secrets
type: Opaque
data:
  openai-api-key: <base64-encoded-api-key>
  anthropic-api-key: <base64-encoded-api-key>
  database-url: <base64-encoded-database-url>
```

### Horizontal Pod Autoscaler

```yaml
# k8s/hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: rcrewai-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: rcrewai-app
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
```

## Configuration Management

### Environment-based Configuration

```ruby
# config/production.rb
class ProductionConfig
  def self.configure
    RCrewAI.configure do |config|
      # LLM Provider Configuration
      config.llm_provider = ENV.fetch('LLM_PROVIDER', 'openai').to_sym
      
      case config.llm_provider
      when :openai
        config.openai_api_key = ENV.fetch('OPENAI_API_KEY')
        config.base_url = ENV['OPENAI_BASE_URL'] # Optional custom endpoint
      when :anthropic
        config.anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY')
      when :azure
        config.azure_api_key = ENV.fetch('AZURE_OPENAI_API_KEY')
        config.base_url = ENV.fetch('AZURE_OPENAI_ENDPOINT')
        config.api_version = ENV.fetch('AZURE_API_VERSION', '2023-05-15')
      when :google
        config.google_api_key = ENV.fetch('GOOGLE_API_KEY')
      end
      
      # Model Parameters
      config.temperature = ENV.fetch('LLM_TEMPERATURE', '0.1').to_f
      config.max_tokens = ENV.fetch('LLM_MAX_TOKENS', '4000').to_i
      config.timeout = ENV.fetch('LLM_TIMEOUT', '60').to_i
      
      # Production Settings
      config.retry_limit = ENV.fetch('LLM_RETRY_LIMIT', '3').to_i
      config.retry_delay = ENV.fetch('LLM_RETRY_DELAY', '2').to_i
      config.max_concurrent_requests = ENV.fetch('MAX_CONCURRENT_REQUESTS', '10').to_i
      
      # Logging
      config.log_level = ENV.fetch('LOG_LEVEL', 'INFO').upcase
      config.structured_logging = ENV.fetch('STRUCTURED_LOGGING', 'true') == 'true'
      
      # Security
      config.validate_ssl = ENV.fetch('VALIDATE_SSL', 'true') == 'true'
      config.user_agent = "RCrewAI/#{RCrewAI::VERSION} (Production)"
    end
  end
  
  def self.database_config
    {
      url: ENV.fetch('DATABASE_URL'),
      pool_size: ENV.fetch('DB_POOL_SIZE', '5').to_i,
      checkout_timeout: ENV.fetch('DB_CHECKOUT_TIMEOUT', '5').to_i,
      reaping_frequency: ENV.fetch('DB_REAPING_FREQUENCY', '10').to_i
    }
  end
  
  def self.redis_config
    {
      url: ENV.fetch('REDIS_URL', 'redis://localhost:6379'),
      timeout: ENV.fetch('REDIS_TIMEOUT', '5').to_i,
      reconnect_attempts: ENV.fetch('REDIS_RECONNECT_ATTEMPTS', '3').to_i
    }
  end
  
  def self.monitoring_config
    {
      metrics_enabled: ENV.fetch('METRICS_ENABLED', 'true') == 'true',
      traces_enabled: ENV.fetch('TRACES_ENABLED', 'true') == 'true',
      health_check_interval: ENV.fetch('HEALTH_CHECK_INTERVAL', '30').to_i,
      performance_monitoring: ENV.fetch('PERFORMANCE_MONITORING', 'true') == 'true'
    }
  end
end
```

### Secrets Management with Vault

```ruby
# config/vault_client.rb
require 'vault'

class VaultClient
  def initialize
    Vault.configure do |config|
      config.address = ENV.fetch('VAULT_ADDR')
      config.token = ENV['VAULT_TOKEN']
      config.ssl_verify = ENV.fetch('VAULT_SSL_VERIFY', 'true') == 'true'
    end
  end
  
  def get_secret(path)
    secret = Vault.logical.read(path)
    secret&.data
  rescue Vault::VaultError => e
    Rails.logger.error "Vault error: #{e.message}"
    raise
  end
  
  def get_database_credentials
    get_secret('secret/data/database')
  end
  
  def get_llm_api_keys
    get_secret('secret/data/llm_providers')
  end
  
  def refresh_secrets
    # Implement secret rotation logic
    new_secrets = get_llm_api_keys
    
    if new_secrets
      ENV['OPENAI_API_KEY'] = new_secrets[:openai_api_key]
      ENV['ANTHROPIC_API_KEY'] = new_secrets[:anthropic_api_key]
      
      # Reconfigure RCrewAI with new secrets
      ProductionConfig.configure
    end
  end
end

# Periodic secret refresh
Thread.new do
  vault_client = VaultClient.new
  
  loop do
    sleep(3600) # Refresh every hour
    
    begin
      vault_client.refresh_secrets
    rescue => e
      Rails.logger.error "Secret refresh failed: #{e.message}"
    end
  end
end
```

## Monitoring and Observability

### Prometheus Metrics

```ruby
# lib/metrics.rb
require 'prometheus/client'

class RCrewAIMetrics
  def initialize
    @registry = Prometheus::Client.registry
    setup_metrics
  end
  
  def setup_metrics
    # Request counters
    @request_total = @registry.counter(
      :rcrewai_requests_total,
      docstring: 'Total number of requests',
      labels: [:method, :path, :status]
    )
    
    @execution_total = @registry.counter(
      :rcrewai_executions_total, 
      docstring: 'Total number of crew executions',
      labels: [:crew_name, :status]
    )
    
    # Duration histograms
    @request_duration = @registry.histogram(
      :rcrewai_request_duration_seconds,
      docstring: 'Request duration in seconds',
      labels: [:method, :path],
      buckets: [0.1, 0.5, 1.0, 5.0, 10.0, 30.0, 60.0]
    )
    
    @execution_duration = @registry.histogram(
      :rcrewai_execution_duration_seconds,
      docstring: 'Crew execution duration in seconds', 
      labels: [:crew_name],
      buckets: [1.0, 5.0, 10.0, 30.0, 60.0, 300.0, 600.0]
    )
    
    # Gauges
    @active_executions = @registry.gauge(
      :rcrewai_active_executions,
      docstring: 'Number of active executions',
      labels: [:crew_name]
    )
    
    @memory_usage = @registry.gauge(
      :rcrewai_memory_usage_bytes,
      docstring: 'Memory usage in bytes'
    )
    
    @llm_api_calls = @registry.counter(
      :rcrewai_llm_api_calls_total,
      docstring: 'Total LLM API calls',
      labels: [:provider, :model, :status]
    )
  end
  
  def record_request(method, path, status, duration)
    @request_total.increment(labels: { method: method, path: path, status: status })
    @request_duration.observe(duration, labels: { method: method, path: path })
  end
  
  def record_execution_start(crew_name)
    @active_executions.increment(labels: { crew_name: crew_name })
  end
  
  def record_execution_complete(crew_name, status, duration)
    @active_executions.decrement(labels: { crew_name: crew_name })
    @execution_total.increment(labels: { crew_name: crew_name, status: status })
    @execution_duration.observe(duration, labels: { crew_name: crew_name })
  end
  
  def record_llm_call(provider, model, status)
    @llm_api_calls.increment(labels: { provider: provider, model: model, status: status })
  end
  
  def update_memory_usage
    memory = get_memory_usage_bytes
    @memory_usage.set(memory)
  end
  
  private
  
  def get_memory_usage_bytes
    `ps -o rss= -p #{Process.pid}`.to_i * 1024
  rescue
    0
  end
end

# Initialize global metrics instance
$metrics = RCrewAIMetrics.new

# Middleware for automatic metrics collection
class MetricsMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    start_time = Time.now
    method = env['REQUEST_METHOD']
    path = env['PATH_INFO']
    
    status, headers, body = @app.call(env)
    
    duration = Time.now - start_time
    $metrics.record_request(method, path, status.to_s, duration)
    
    [status, headers, body]
  end
end
```

### Structured Logging

```ruby
# lib/structured_logger.rb
require 'json'
require 'logger'

class StructuredLogger
  def initialize(output = $stdout)
    @logger = Logger.new(output)
    @logger.level = Logger.const_get(ENV.fetch('LOG_LEVEL', 'INFO'))
    @logger.formatter = method(:json_formatter)
  end
  
  def info(message, context = {})
    @logger.info(log_entry(message, context))
  end
  
  def warn(message, context = {})
    @logger.warn(log_entry(message, context))
  end
  
  def error(message, context = {})
    @logger.error(log_entry(message, context))
  end
  
  def debug(message, context = {})
    @logger.debug(log_entry(message, context))
  end
  
  private
  
  def log_entry(message, context)
    {
      timestamp: Time.now.utc.iso8601,
      level: caller_locations(2, 1)[0].label.upcase,
      message: message,
      service: 'rcrewai',
      version: RCrewAI::VERSION,
      environment: ENV.fetch('RAILS_ENV', 'development'),
      process_id: Process.pid,
      thread_id: Thread.current.object_id
    }.merge(context)
  end
  
  def json_formatter(severity, timestamp, progname, msg)
    if msg.is_a?(Hash)
      msg.to_json + "\n"
    else
      {
        timestamp: timestamp.utc.iso8601,
        level: severity,
        message: msg.to_s,
        service: 'rcrewai'
      }.to_json + "\n"
    end
  end
end

# Global logger instance
$logger = StructuredLogger.new
```

### Distributed Tracing

```ruby
# lib/tracing.rb
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/jaeger'
require 'opentelemetry/instrumentation/all'

class TracingSetup
  def self.configure
    OpenTelemetry::SDK.configure do |c|
      c.service_name = 'rcrewai'
      c.service_version = RCrewAI::VERSION
      
      c.add_span_processor(
        OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
          OpenTelemetry::Exporter::Jaeger::AgentExporter.new(
            endpoint: ENV.fetch('JAEGER_AGENT_HOST', 'localhost:14268')
          )
        )
      )
      
      c.use_all() # Enable all instrumentations
    end
  end
  
  def self.tracer
    OpenTelemetry.tracer_provider.tracer('rcrewai', RCrewAI::VERSION)
  end
end

# Initialize tracing
TracingSetup.configure if ENV.fetch('TRACING_ENABLED', 'true') == 'true'

# Tracing middleware
class TracingMiddleware
  def initialize(app)
    @app = app
    @tracer = TracingSetup.tracer
  end
  
  def call(env)
    @tracer.in_span("http_request") do |span|
      span.set_attribute('http.method', env['REQUEST_METHOD'])
      span.set_attribute('http.url', env['PATH_INFO'])
      
      status, headers, body = @app.call(env)
      
      span.set_attribute('http.status_code', status)
      span.status = OpenTelemetry::Trace::Status.error if status >= 400
      
      [status, headers, body]
    end
  end
end
```

## Scaling and Load Balancing

### Auto-scaling Configuration

```yaml
# k8s/vertical-pod-autoscaler.yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: rcrewai-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: rcrewai-app
  updatePolicy:
    updateMode: "Auto"
  resourcePolicy:
    containerPolicies:
    - containerName: rcrewai
      minAllowed:
        cpu: 100m
        memory: 128Mi
      maxAllowed:
        cpu: 1
        memory: 1Gi
```

### Load Balancer Configuration

```nginx
# nginx.conf
upstream rcrewai_backend {
    least_conn;
    server rcrewai-1:8080 max_fails=3 fail_timeout=30s;
    server rcrewai-2:8080 max_fails=3 fail_timeout=30s;
    server rcrewai-3:8080 max_fails=3 fail_timeout=30s;
}

server {
    listen 80;
    server_name api.yourcompany.com;
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req zone=api burst=20 nodelay;
    
    # Request timeout
    proxy_read_timeout 300s;
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    
    location / {
        proxy_pass http://rcrewai_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Health check
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_next_upstream_tries 3;
        proxy_next_upstream_timeout 60s;
    }
    
    location /health {
        access_log off;
        proxy_pass http://rcrewai_backend;
    }
    
    location /metrics {
        access_log off;
        allow 10.0.0.0/8;
        allow 192.168.0.0/16;
        deny all;
        proxy_pass http://rcrewai_backend;
    }
}
```

## Security and Access Control

### Network Policies

```yaml
# k8s/network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: rcrewai-network-policy
spec:
  podSelector:
    matchLabels:
      app: rcrewai
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-system
    - podSelector:
        matchLabels:
          app: load-balancer
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to: []
    ports:
    - protocol: TCP
      port: 443  # HTTPS
    - protocol: TCP  
      port: 53   # DNS
    - protocol: UDP
      port: 53   # DNS
  - to:
    - podSelector:
        matchLabels:
          app: redis
    ports:
    - protocol: TCP
      port: 6379
```

### Pod Security Standards

```yaml
# k8s/pod-security-policy.yaml
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: rcrewai-psp
spec:
  privileged: false
  allowPrivilegeEscalation: false
  requiredDropCapabilities:
    - ALL
  volumes:
    - 'configMap'
    - 'emptyDir'
    - 'projected'
    - 'secret'
    - 'downwardAPI'
    - 'persistentVolumeClaim'
  runAsUser:
    rule: 'MustRunAsNonRoot'
  seLinux:
    rule: 'RunAsAny'
  fsGroup:
    rule: 'RunAsAny'
```

### Authentication and Authorization

```ruby
# lib/auth.rb
require 'jwt'

class AuthenticationMiddleware
  def initialize(app)
    @app = app
    @secret = ENV.fetch('JWT_SECRET')
  end
  
  def call(env)
    # Skip auth for health checks
    if env['PATH_INFO'] == '/health' || env['PATH_INFO'] == '/ready'
      return @app.call(env)
    end
    
    auth_header = env['HTTP_AUTHORIZATION']
    
    unless auth_header&.start_with?('Bearer ')
      return unauthorized_response
    end
    
    token = auth_header.sub('Bearer ', '')
    
    begin
      payload = JWT.decode(token, @secret, true, algorithm: 'HS256')[0]
      env['user_id'] = payload['user_id']
      env['permissions'] = payload['permissions'] || []
      
      @app.call(env)
    rescue JWT::DecodeError
      unauthorized_response
    end
  end
  
  private
  
  def unauthorized_response
    [401, {'Content-Type' => 'application/json'}, [
      { error: 'Unauthorized' }.to_json
    ]]
  end
end

class AuthorizationMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    permissions = env['permissions'] || []
    path = env['PATH_INFO']
    method = env['REQUEST_METHOD']
    
    required_permission = determine_required_permission(method, path)
    
    if required_permission && !permissions.include?(required_permission)
      return forbidden_response
    end
    
    @app.call(env)
  end
  
  private
  
  def determine_required_permission(method, path)
    case [method, path]
    when ['POST', '/execute']
      'execute_crew'
    when ['GET', '/metrics']
      'view_metrics'
    else
      nil # No special permission required
    end
  end
  
  def forbidden_response
    [403, {'Content-Type' => 'application/json'}, [
      { error: 'Forbidden' }.to_json
    ]]
  end
end
```

## CI/CD Pipeline

### GitHub Actions Workflow

```yaml
# .github/workflows/deploy.yml
name: Deploy to Production

on:
  push:
    branches: [main]
    tags: ['v*']

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Ruby
      uses: ruby/setup-ruby@v1
      with:
        ruby-version: 3.1
        bundler-cache: true
    
    - name: Run tests
      run: bundle exec rspec
      
    - name: Run security scan
      run: |
        bundle exec bundle-audit check --update
        bundle exec brakeman -q -w2
    
    - name: Check code style
      run: bundle exec rubocop

  build:
    needs: test
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
    - uses: actions/checkout@v3
    
    - name: Log in to Container Registry
      uses: docker/login-action@v2
      with:
        registry: ${{ env.REGISTRY }}
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
    
    - name: Extract metadata
      id: meta
      uses: docker/metadata-action@v4
      with:
        images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
        tags: |
          type=ref,event=branch
          type=ref,event=pr
          type=semver,pattern={{version}}
          type=semver,pattern={{major}}.{{minor}}
    
    - name: Build and push Docker image
      uses: docker/build-push-action@v4
      with:
        context: .
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment: production
    if: github.ref == 'refs/heads/main'
    steps:
    - uses: actions/checkout@v3
    
    - name: Configure kubectl
      uses: azure/k8s-set-context@v1
      with:
        method: kubeconfig
        kubeconfig: ${{ secrets.KUBE_CONFIG }}
    
    - name: Deploy to Kubernetes
      run: |
        kubectl set image deployment/rcrewai-app \
          rcrewai=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
        kubectl rollout status deployment/rcrewai-app --timeout=600s
    
    - name: Run smoke tests
      run: |
        kubectl wait --for=condition=ready pod -l app=rcrewai --timeout=300s
        ./scripts/smoke-tests.sh
```

### Deployment Scripts

```bash
#!/bin/bash
# scripts/deploy.sh

set -euo pipefail

ENVIRONMENT=${1:-production}
IMAGE_TAG=${2:-latest}

echo "Deploying RCrewAI to $ENVIRONMENT with tag $IMAGE_TAG"

# Update deployment with new image
kubectl set image deployment/rcrewai-app \
  rcrewai="ghcr.io/yourorg/rcrewai:$IMAGE_TAG" \
  --namespace="$ENVIRONMENT"

# Wait for rollout to complete
kubectl rollout status deployment/rcrewai-app \
  --namespace="$ENVIRONMENT" \
  --timeout=600s

# Verify deployment
echo "Verifying deployment..."
kubectl get pods -l app=rcrewai --namespace="$ENVIRONMENT"

# Run health check
echo "Running health check..."
HEALTH_URL=$(kubectl get service rcrewai-service --namespace="$ENVIRONMENT" \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

curl -f "http://$HEALTH_URL/health" || {
  echo "Health check failed!"
  exit 1
}

echo "Deployment successful!"
```

```bash
#!/bin/bash
# scripts/smoke-tests.sh

set -euo pipefail

SERVICE_URL=${SERVICE_URL:-http://localhost:8080}

echo "Running smoke tests against $SERVICE_URL"

# Test 1: Health check
echo "Testing health endpoint..."
response=$(curl -s -o /dev/null -w "%{http_code}" "$SERVICE_URL/health")
if [[ $response != "200" ]]; then
  echo "Health check failed: $response"
  exit 1
fi

# Test 2: Ready check
echo "Testing readiness endpoint..."
response=$(curl -s -o /dev/null -w "%{http_code}" "$SERVICE_URL/ready")
if [[ $response != "200" ]]; then
  echo "Readiness check failed: $response"
  exit 1
fi

# Test 3: Metrics endpoint
echo "Testing metrics endpoint..."
response=$(curl -s -o /dev/null -w "%{http_code}" "$SERVICE_URL/metrics")
if [[ $response != "200" ]] && [[ $response != "403" ]]; then
  echo "Metrics check failed: $response"
  exit 1
fi

# Test 4: Basic execution (if auth allows)
echo "Testing basic execution..."
response=$(curl -s -X POST "$SERVICE_URL/execute" \
  -H "Content-Type: application/json" \
  -d '{"crew_name": "customer_support", "request_id": "test-123"}' \
  -w "%{http_code}" -o /dev/null)

# Accept 401/403 for auth-protected endpoints
if [[ $response != "200" ]] && [[ $response != "401" ]] && [[ $response != "403" ]]; then
  echo "Execution test failed: $response"
  exit 1
fi

echo "All smoke tests passed!"
```

## Operational Procedures

### Monitoring Dashboard

```yaml
# grafana/dashboards/rcrewai-dashboard.json
{
  "dashboard": {
    "title": "RCrewAI Production Dashboard",
    "panels": [
      {
        "title": "Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(rcrewai_requests_total[5m])",
            "legendFormat": "{{method}} {{path}}"
          }
        ]
      },
      {
        "title": "Response Times", 
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(rcrewai_request_duration_seconds_bucket[5m]))",
            "legendFormat": "95th percentile"
          },
          {
            "expr": "histogram_quantile(0.50, rate(rcrewai_request_duration_seconds_bucket[5m]))",
            "legendFormat": "50th percentile"
          }
        ]
      },
      {
        "title": "Error Rate",
        "type": "stat",
        "targets": [
          {
            "expr": "rate(rcrewai_requests_total{status=~\"5..\"}[5m]) / rate(rcrewai_requests_total[5m]) * 100",
            "legendFormat": "Error Rate %"
          }
        ]
      },
      {
        "title": "Crew Executions",
        "type": "graph", 
        "targets": [
          {
            "expr": "rate(rcrewai_executions_total[5m])",
            "legendFormat": "{{crew_name}} {{status}}"
          }
        ]
      },
      {
        "title": "Memory Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "rcrewai_memory_usage_bytes / 1024 / 1024",
            "legendFormat": "Memory MB"
          }
        ]
      },
      {
        "title": "Active Executions",
        "type": "stat",
        "targets": [
          {
            "expr": "sum(rcrewai_active_executions)",
            "legendFormat": "Active"
          }
        ]
      }
    ]
  }
}
```

### Alerting Rules

```yaml
# prometheus/alerts.yml
groups:
- name: rcrewai
  rules:
  - alert: HighErrorRate
    expr: rate(rcrewai_requests_total{status=~"5.."}[5m]) / rate(rcrewai_requests_total[5m]) > 0.05
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "High error rate detected"
      description: "Error rate is {{ $value }}% for the last 5 minutes"
      
  - alert: HighResponseTime
    expr: histogram_quantile(0.95, rate(rcrewai_request_duration_seconds_bucket[5m])) > 10
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High response time detected"
      description: "95th percentile response time is {{ $value }}s"
      
  - alert: ServiceDown
    expr: up{job="rcrewai"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "RCrewAI service is down"
      description: "RCrewAI service has been down for more than 1 minute"
      
  - alert: HighMemoryUsage
    expr: rcrewai_memory_usage_bytes / 1024 / 1024 / 1024 > 1
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High memory usage"
      description: "Memory usage is {{ $value }}GB"
      
  - alert: TooManyActiveExecutions
    expr: sum(rcrewai_active_executions) > 50
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "Too many active executions"
      description: "{{ $value }} executions are currently active"
```

### Backup and Recovery

```bash
#!/bin/bash
# scripts/backup.sh

set -euo pipefail

BACKUP_DIR=${BACKUP_DIR:-/backups}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "Starting backup at $TIMESTAMP"

# Backup configuration
kubectl get configmap rcrewai-config -o yaml > "$BACKUP_DIR/config_$TIMESTAMP.yaml"
kubectl get secret rcrewai-secrets -o yaml > "$BACKUP_DIR/secrets_$TIMESTAMP.yaml"

# Backup persistent data (if any)
if kubectl get pvc rcrewai-data 2>/dev/null; then
  kubectl exec -it deployment/rcrewai-app -- tar czf - /data > "$BACKUP_DIR/data_$TIMESTAMP.tar.gz"
fi

# Cleanup old backups (keep last 30 days)
find "$BACKUP_DIR" -name "*.yaml" -mtime +30 -delete
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +30 -delete

echo "Backup completed successfully"
```

## Troubleshooting and Recovery

### Common Issues and Solutions

#### High Memory Usage
```bash
# Check memory usage
kubectl top pods -l app=rcrewai

# Check for memory leaks
kubectl exec -it deployment/rcrewai-app -- ps aux

# Restart pods if needed
kubectl rollout restart deployment/rcrewai-app
```

#### Slow Response Times
```bash
# Check CPU usage
kubectl top pods -l app=rcrewai

# Scale up if needed
kubectl scale deployment rcrewai-app --replicas=5

# Check database connections
kubectl logs deployment/rcrewai-app | grep -i "database\|connection"
```

#### Failed Deployments
```bash
# Check rollout status
kubectl rollout status deployment/rcrewai-app

# Check pod logs
kubectl logs deployment/rcrewai-app --previous

# Rollback if needed
kubectl rollout undo deployment/rcrewai-app
```

### Recovery Procedures

#### Complete Service Recovery
```bash
#!/bin/bash
# scripts/disaster-recovery.sh

set -euo pipefail

echo "Starting disaster recovery procedure"

# 1. Restore configuration
kubectl apply -f backups/config_latest.yaml
kubectl apply -f backups/secrets_latest.yaml

# 2. Deploy application
kubectl apply -f k8s/

# 3. Wait for deployment
kubectl wait --for=condition=available deployment/rcrewai-app --timeout=600s

# 4. Restore data if needed
if [[ -f "backups/data_latest.tar.gz" ]]; then
  kubectl exec -it deployment/rcrewai-app -- tar xzf - -C / < backups/data_latest.tar.gz
fi

# 5. Verify service
./scripts/smoke-tests.sh

echo "Disaster recovery completed"
```

## Best Practices Summary

### 1. **Security**
- Use non-root containers
- Implement network policies
- Manage secrets properly
- Enable authentication and authorization
- Regular security scans

### 2. **Reliability**
- Health and readiness checks
- Resource limits and requests  
- Graceful shutdown handling
- Circuit breakers for external calls
- Comprehensive error handling

### 3. **Scalability**
- Horizontal pod autoscaling
- Load balancing
- Stateless application design
- Resource optimization
- Performance monitoring

### 4. **Observability**
- Structured logging
- Comprehensive metrics
- Distributed tracing
- Real-time alerting
- Dashboard visualization

### 5. **Operations**
- Automated deployments
- Blue-green deployments
- Backup and recovery procedures
- Incident response playbooks
- Regular performance reviews

This production deployment guide provides a comprehensive foundation for running RCrewAI applications at scale with enterprise-grade reliability, security, and observability.