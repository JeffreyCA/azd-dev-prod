# 🌍 Multi-Region Scale Unit Architecture

This project implements a highly available, multi-region Flask application with automatic failover and global load balancing using Azure services. The infrastructure is organized into **global** and **regional** modules for better maintainability and deployment efficiency.

## 🏗️ Architecture Overview

### Infrastructure Organization

The Bicep infrastructure has been reorganized into a modular architecture:

```
infra-staged/
├── main.bicep                    # Main orchestration (subscription scope)
├── main.parameters.json          # Environment parameters
├── global/                       # Global infrastructure components
│   ├── main.bicep               # Global resources (Front Door, DNS, shared storage)
│   └── front-door-config.bicep  # Front Door endpoint configuration
└── regional/                     # Regional infrastructure components
    ├── main.bicep               # Regional orchestration
    ├── app.bicep                # App Service and hosting
    ├── storage.bicep            # Regional storage
    ├── network.bicep            # VNet and networking
    ├── monitoring.bicep         # Regional monitoring
    └── modules/                 # Additional modules
```

### Deployment Model

- **Single Resource Group**: All resources are deployed to one resource group for simplified management
- **Global Components**: Front Door, DNS zones, and shared storage deployed once
- **Regional Components**: App Services, regional storage, and monitoring deployed per region
- **Service Configuration**: Two azd services (`app-primary` and `app-secondary`) for automatic deployment

### Production Environment (`envType = 'prod'`)
```
┌─────────────────────────────────────────────────────────────────────┐
│                           Azure Front Door                          │
│                    (Global Load Balancer + CDN)                     │
└─────────────┬───────────────────────────────────┬───────────────────┘
              │                                   │
    ┌─────────▼─────────┐                ┌─────────▼─────────┐
    │   PRIMARY REGION  │                │  SECONDARY REGION │
    │                   │                │                   │
    │  ┌─────────────┐  │                │  ┌─────────────┐  │
    │  │ App Service │  │                │  │ App Service │  │
    │  │ (VNet Integ)│  │                │  │ (VNet Integ)│  │
    │  └──────┬──────┘  │                │  └──────┬──────┘  │
    │         │         │                │         │         │
    │  ┌──────▼──────┐  │                │  ┌──────▼──────┐  │
    │  │ VNet + Priv │  │                │  │ VNet + Priv │  │
    │  │ Endpoints   │  │                │  │ Endpoints   │  │
    │  └──────┬──────┘  │                │  └──────┬──────┘  │
    │         │         │                │         │         │
    │  ┌──────▼──────┐  │                │  ┌──────▼──────┐  │
    │  │ Storage     │  │                │  │ Storage     │  │
    │  │ (Private)   │  │                │  │ (Private)   │  │
    │  └─────────────┘  │                │  └─────────────┘  │
    └───────────────────┘                └───────────────────┘
              │                                   │
              └─────────────┬─────────────────────┘
                            │
                   ┌────────▼────────┐
                   │ Global Storage  │
                   │ (Shared Config) │
                   └─────────────────┘
```

### Development Environment (`envType = 'dev'`)
```
┌─────────────────────────────────────────────────────────────────────┐
│                           Azure Front Door                          │
│                    (Global Load Balancer + CDN)                     │
└─────────────┬───────────────────────────────────┬───────────────────┘
              │                                   │
    ┌─────────▼─────────┐                ┌─────────▼─────────┐
    │   PRIMARY REGION  │                │  SECONDARY REGION │
    │                   │                │                   │
    │  ┌─────────────┐  │                │  ┌─────────────┐  │
    │  │ App Service │  │                │  │ App Service │  │
    │  │ (Simplified)│  │                │  │ (Simplified)│  │
    │  └──────┬──────┘  │                │  └──────┬──────┘  │
    │         │         │                │         │         │
    │  ┌──────▼──────┐  │                │  ┌──────▼──────┐  │
    │  │ Storage     │  │                │  │ Storage     │  │
    │  │ (Public +   │  │                │  │ (Public +   │  │
    │  │  MI Auth)   │  │                │  │  MI Auth)   │  │
    │  └─────────────┘  │                │  └─────────────┘  │
    └───────────────────┘                └───────────────────┘
```

## 🚀 Quick Start

### Prerequisites
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
- Azure subscription with appropriate permissions

### Quick Deployment

```bash
# Clone and navigate to the project
cd azd-dev-prod-appservice-storage

# Deploy using azd
azd up

# Or deploy specific environment
azd env set AZURE_ENV_TYPE prod
azd up
```

### Service Configuration

The project now uses a dual-service model in `azure.yaml`:

```yaml
services:
  app-primary:     # Deployed to primary region
    project: .
    host: appservice
    language: python
  app-secondary:   # Deployed to secondary region  
    project: .
    host: appservice
    language: python
```

### Alternative Deployment Methods
```bash
# Set environment variables
export AZURE_ENV_NAME="my-scale-unit"
export AZURE_ENV_TYPE="dev"
export AZURE_LOCATION="eastus2"
export AZURE_SECONDARY_LOCATION="southcentralus"

# Deploy
azd up
```

## 🔧 Configuration Options

### Environment Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `AZURE_ENV_NAME` | Environment name for resource naming | - | `my-scale-unit` |
| `AZURE_ENV_TYPE` | Environment type (dev/test/prod) | `dev` | `prod` |
| `AZURE_LOCATION` | Primary region | `eastus` | `eastus2` |
| `AZURE_SECONDARY_LOCATION` | Secondary region | `westus2` | `southcentralus` |

### azd Configuration

Update environment values:
```bash
# Set environment type
azd env set AZURE_ENV_TYPE prod

# Set regions
azd env set AZURE_LOCATION eastus2
azd env set AZURE_SECONDARY_LOCATION southcentralus

# Deploy with new configuration
azd up
```

### Environment Types

| Environment | Networking | Security | Use Case |
|------------|------------|----------|----------|
| `dev` | Public access with MI auth | Basic | Development, testing |
| `test` | Public access with MI auth | Basic | Integration testing |
| `prod` | VNet integration + private endpoints | High | Production workloads |

### Regions

Default regions (optimized for reliability and quota availability):
- **Primary**: East US 2 (`eastus2`)
- **Secondary**: South Central US (`southcentralus`)

**Recommended Region Pairs:**
- **US**: `eastus2` + `southcentralus` or `centralus` + `westcentralus`  
- **Europe**: `northeurope` + `westeurope`
- **Asia**: `eastasia` + `southeastasia`

To use different regions:
```bash
azd env set AZURE_LOCATION northeurope
azd env set AZURE_SECONDARY_LOCATION westeurope
azd up
```

## 📊 Monitoring & Health Checks

### Built-in Health Endpoints

The Flask application includes health endpoints for Front Door integration:

- **`/health`** - Health check endpoint for Front Door health probes
  ```json
  {
    "status": "healthy",
    "region": "primary",
    "timestamp": "2025-07-02T10:30:00Z"
  }
  ```

- **`/info`** - Application information and diagnostics
  ```json
  {
    "app": "Flask Multi-Region Demo",
    "version": "1.0.0",
    "region": "primary",
    "storage_account": "st...",
    "environment": "dev"
  }
  ```

### Monitoring Architecture

**Global Components:**
- **Azure Front Door** - Global load balancing, CDN, and health probing
- **Global Application Insights** - Aggregated telemetry and metrics

**Regional Components:**
- **Regional Application Insights** - Region-specific performance monitoring  
- **Log Analytics Workspace** - Centralized logging per region
- **Portal Dashboards** - Regional monitoring dashboards
- **Metric Alerts** - Health and performance alerting

### Infrastructure Organization

The monitoring is organized as follows:
- **Global Monitoring**: Front Door analytics and global application insights
- **Regional Monitoring**: Per-region App Service metrics, logs, and alerts
- **Cross-Region Correlation**: Shared resource tokens enable correlation across regions

### Key Metrics to Monitor

- Front Door availability percentage
- App Service response times
- Storage account accessibility
- CPU and memory utilization
- Request success rates

## 🛡️ Security Features

### Production Security (`envType = 'prod'`)

- **Network Isolation**: VNet integration with private endpoints
- **Storage Security**: Private-only access to storage accounts
- **Identity Management**: Managed identities for all authentication
- **Transport Security**: HTTPS-only with TLS 1.2 minimum
- **Access Controls**: Network ACLs and IP restrictions

### Development Security (`envType = 'dev'`)

- **Managed Identity**: Passwordless authentication
- **HTTPS Enforcement**: Secure transport
- **Storage Access**: Public with managed identity auth
- **Basic Network Controls**: Azure service bypass

## 🔄 High Availability Features

### Automatic Failover

1. **Health Probes**: Front Door continuously monitors `/health` endpoint
2. **Priority Routing**: Primary region gets priority 1, secondary gets priority 2
3. **Automatic Failover**: Traffic automatically routes to healthy regions
4. **Geographic Distribution**: Users are served from the closest healthy region

### Scaling & Performance

- **Auto-scaling**: CPU-based scaling (70% scale up, 30% scale down)
- **Regional Capacity**: Primary region supports 2-10 instances, secondary 1-5
- **CDN**: Global content delivery network for improved performance
- **Connection Pooling**: Optimized database and storage connections

## 🧪 Testing Failover

### Simulate Region Failure

1. **Stop Primary Region App Service**:
   ```bash
   az webapp stop --name <primary-app-name> --resource-group <primary-rg>
   ```

2. **Monitor Front Door**: Traffic should automatically route to secondary region

3. **Restart Primary Region**:
   ```bash
   az webapp start --name <primary-app-name> --resource-group <primary-rg>
   ```

### Health Check Testing

```bash
# Test health endpoints
curl https://<front-door-endpoint>/health
curl https://<front-door-endpoint>/info

# Test primary region directly
curl https://<primary-app-service>/health

# Test secondary region directly
curl https://<secondary-app-service>/health
```

## 📋 Management Commands

### Primary Deployment Commands
```bash
# Full deployment (infrastructure + application)
azd up

# Deploy only application code (faster for code changes)
azd deploy

# Deploy specific service
azd deploy app-primary

# Preview infrastructure changes
azd provision --preview

# View real-time logs from both regions
azd logs

# Monitor application performance
azd monitor
```

### Environment Management
```bash
# List all environments
azd env list

# Switch to different environment
azd env select <environment-name>

# View current environment values
azd env get-values

# Set specific environment values
azd env set AZURE_ENV_TYPE=prod
azd env set AZURE_LOCATION=northeurope

# Create new environment
azd env new <environment-name>
```

### Infrastructure Management  
```bash
# View deployment outputs
azd show --output table

# Get Front Door endpoint
azd env get-values | grep FRONT_DOOR

# Clean up all resources
azd down --force --purge
```

## 🛠️ Infrastructure Details

### Bicep Module Organization

The infrastructure is modular and organized for maintainability:

**Main Orchestration (`main.bicep`):**
- Subscription-scoped deployment
- Single resource group creation
- Orchestrates global and regional deployments
- Parameter management and output aggregation

**Global Infrastructure (`global/`):**
- **`main.bicep`**: Front Door profile, DNS zones, global storage
- **`front-door-config.bicep`**: Endpoint and origin configuration (post-deployment)

**Regional Infrastructure (`regional/`):**
- **`main.bicep`**: Regional orchestration and resource coordination
- **`app.bicep`**: App Service Plan and App Service configuration
- **`storage.bicep`**: Regional storage accounts and containers
- **`network.bicep`**: VNet, subnets, and private endpoints (prod only)
- **`monitoring.bicep`**: Application Insights, Log Analytics, and dashboards

### Deployment Flow

1. **Global Resources**: DNS zones, Front Door profile, shared storage
2. **Regional Resources**: App Services, regional storage, monitoring (parallel deployment)
3. **Front Door Configuration**: Endpoints and origins (after App Services are ready)
4. **Application Deployment**: Code deployment to both regions via azd services

### Service Tags and Naming

The infrastructure uses consistent tagging for azd integration:
- App Services tagged with `azd-service-name`: `app-primary` and `app-secondary`
- Resource naming follows Azure abbreviation standards
- Unique resource tokens ensure global name uniqueness

## 🛠️ Troubleshooting

### Common Deployment Issues

1. **Quota Exceeded Errors**
   ```
   Error: Quota exceeded for App Service Plan
   ```
   **Solution**: Try different regions or F1 SKU
   ```bash
   azd env set AZURE_LOCATION eastus2
   azd env set AZURE_SECONDARY_LOCATION southcentralus
   azd up
   ```

2. **Service Tag Mismatch**
   ```
   Error: Unable to find service for deployment
   ```
   **Solution**: Ensure App Service tags match azure.yaml services
   - App Services must be tagged: `app-primary` and `app-secondary`

3. **Front Door Configuration Issues**
   - Check health endpoints are accessible: `/health`
   - Verify App Service hostnames are correct
   - Monitor Front Door health probe status

### Diagnostic Commands

```bash
# Check deployment status
azd show

# View service-specific logs  
azd logs app-primary
azd logs app-secondary

# Check resource health
az resource list --resource-group rg-<env-name> --output table

# Test health endpoints
curl https://<front-door-endpoint>/health
curl https://<app-service-hostname>/health
```

### Regional Failover Testing

```bash
# Stop primary region App Service
az webapp stop --name <primary-app-name> --resource-group rg-<env-name>

# Monitor Front Door routing (should redirect to secondary)
curl https://<front-door-endpoint>/info

# Restart primary region
az webapp start --name <primary-app-name> --resource-group rg-<env-name>
```

## 🔮 Advanced Scenarios

### Extending the Architecture

**Adding More Regions:**
1. Modify `main.bicep` to add additional regional deployments
2. Update `azure.yaml` to include new service configurations
3. Configure Front Door origin groups for additional regions

**Custom Domains & SSL:**
1. Configure custom domain in Front Door endpoint
2. Upload SSL certificates or use managed certificates  
3. Update DNS CNAME records to point to Front Door

**Database Integration:**
1. Add Azure SQL Database with geo-replication to `global/main.bicep`
2. Configure connection strings per region in `regional/app.bicep`
3. Implement database failover logic in application code

### Production Hardening

**Security Enhancements:**
- Enable WAF (Web Application Firewall) on Front Door
- Configure App Service IP restrictions to Front Door only
- Add Azure Key Vault for secrets management
- Enable Azure AD authentication

**Performance Optimization:**
- Configure Front Door caching rules
- Enable compression and optimization
- Add Application Gateway for advanced load balancing
- Implement Redis cache for session state

### Multi-Environment Strategy

**Development Workflow:**
```bash
# Development environment
azd env new dev-feature-x
azd env set AZURE_ENV_TYPE dev
azd up

# Staging environment  
azd env new staging
azd env set AZURE_ENV_TYPE test
azd up

# Production deployment
azd env new production
azd env set AZURE_ENV_TYPE prod
azd up
```

## 📚 Additional Resources

- [Azure Front Door Documentation](https://docs.microsoft.com/azure/frontdoor/)
- [Azure App Service Multi-Region](https://docs.microsoft.com/azure/app-service/app-service-web-tutorial-content-delivery-network)
- [Azure Developer CLI Documentation](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [Azure Well-Architected Framework](https://docs.microsoft.com/azure/architecture/framework/)
