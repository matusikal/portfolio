readme_content = """# AWS Portfolio Website

## Live at [aleksandermatusik.xyz](https://aleksandermatusik.xyz)

Welcome to the repository for my cloud-native, serverless portfolio website. This project showcases a fully automated, secure, and highly scalable static website hosted on AWS, featuring a real-time serverless visitor counter backend.

---

## Architecture

The following diagram illustrates the end-to-end architecture of the portfolio application, covering the frontend hosting, backend metrics tracking, security layers, and the CI/CD deployment pipeline.

```mermaid
graph TD
    %% Users and Frontend Edge
    User([User Browser]) -->|HTTPS Requests| WAF[AWS WAF <br><small>Rate Limiting & Protection</small>]
    WAF --> CF[Amazon CloudFront <br><small>CDN & Edge Caching</small>]
    CF -->|Fetch Static Assets| S3[(Amazon S3 <br><small>Static Website Bucket</small>)]

    %% Backend API Flow
    User -->|API Call: Update/Get Count| APIGW[API Gateway <br><small>HTTP API</small>]
    APIGW -->|Trigger Function| Lambda[AWS Lambda <br><small>Visitor Counter Logic</small>]
    Lambda -->|Atomic Update / Query| DynamoDB[(Amazon DynamoDB <br><small>Logging Counter Table</small>)]

    %% CI/CD Deployment Pipeline
    GitHub[GitHub Actions Pipeline] -->|1. Authenticate via OIDC| IAM[AWS IAM <br><small>OIDC Provider / AssumeRole</small>]
    IAM -->|2. Short-lived Tokens| GitHub
    GitHub -->|3. Sync Build Artifacts| S3
    GitHub -->|4. Invalidate Cache| CF

    %% Styling
    style User fill:#f9f9f9,stroke:#333,stroke-width:2px
    style WAF fill:#ff9999,stroke:#cc0000,stroke-width:1px
    style CF fill:#ffcc99,stroke:#ff6600,stroke-width:1px
    style S3 fill:#99ccff,stroke:#0066cc,stroke-width:1px
    style APIGW fill:#ccffcc,stroke:#00cc00,stroke-width:1px
    style Lambda fill:#ffff99,stroke:#cccc00,stroke-width:1px
    style DynamoDB fill:#d9b3ff,stroke:#6600cc,stroke-width:1px
    style GitHub fill:#ebebeb,stroke:#666,stroke-width:1px
    style IAM fill:#ffb3d9,stroke:#cc0066,stroke-width:1px
```