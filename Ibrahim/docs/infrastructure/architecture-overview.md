# OMNIA - Cloud & Infrastructure Architecture

## 1. Overview
OMNIA uses a lightweight, reliable, and secure cloud stack on AWS designed for gradual scaling without unnecessary microservice complexity[cite: 3, 4].

## 2. Core Stack
* **Frontend Mobile**: Flutter[cite: 3, 4]
* **Backend API**: Django REST Framework[cite: 3, 4]
* **Database**: PostgreSQL (AWS RDS)[cite: 3, 4]
* **Object Storage**: Amazon S3[cite: 3, 4]
* **Monitoring & Logs**: Amazon CloudWatch[cite: 3, 4]
* **CI/CD**: GitHub Actions[cite: 3, 4]

## 3. Architecture Flow
```text
[ Flutter Mobile App ] 
         │ (HTTPS)
         ▼
[ Django REST API ] ──► [ Amazon S3 (Media/Uploads) ]
         │
         ├──► [ PostgreSQL / RDS Database ]
         └──► [ Amazon CloudWatch (Logs & Metrics) ]

## 4. Environment Strategy
* **Development**: Local Docker Compose stack[cite: 4].
* **Staging**: Controlled AWS environment for pre-release testing and security verification[cite: 4].
* **Production**: Scaled AWS infrastructure with strict access controls and automated backups[cite: 4].

## 5. Security Responsibility Matrix (Ibrahim & Umair)
* **Ibrahim (Cloud & DevOps Owner)**: Implementation and operation of AWS resources, CI/CD pipelines, Docker configs, backups, and log streaming[cite: 4].
* **Umair (Cloud Infrastructure Security)**: IAM policy review, security audits, network hardening, and vulnerability validation[cite: 4].
