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

# Deploy using azd (AZURE_ENV_TYPE=dev by default)
azd up

# Or deploy specific environment
azd env set AZURE_ENV_TYPE prod
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

### Environment Types

| Environment | Networking | Security | Use Case |
|------------|------------|----------|----------|
| `dev` | Public access with MI auth | Basic | Development, testing |
| `prod` | VNet integration + private endpoints | High | Production workloads |

## 📊 Monitoring & Health Checks

### Built-in Health Endpoints

The Flask application includes health endpoints for Front Door integration:

- **`/health`** - Health check endpoint for Front Door health probes
- **`/info`** - Application information and diagnostics

### Health Status Control System

The application includes a **Health Status Control** section on the main page for testing load balancer and Front Door failover:

**Features:**
- **🟢 Make Healthy** button - Sets status to healthy immediately
- **🔴 Make Unhealthy (60s)** button - Temporarily sets status to unhealthy for 60 seconds
- **Auto-Recovery** - Status automatically returns to healthy after 60 seconds
- **Real-time Status Display** - Shows current health status on the page

**How to Test Failover:**
1. Visit your application's main page
2. Click **"Make Unhealthy (60s)"** button
3. Test your Front Door endpoint - traffic should route to the secondary region
4. Wait 60 seconds for auto-recovery, or click **"Make Healthy"** to restore immediately

This allows you to easily test multi-region failover behavior without stopping services.

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

## 🧪 Alternative for testing failover

**Stop App Service:**
```bash
# Stop primary region
az webapp stop --name <primary-app-name> --resource-group <resource-group>

# Restart primary region  
az webapp start --name <primary-app-name> --resource-group <resource-group>
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
