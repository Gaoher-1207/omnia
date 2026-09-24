# OMNIA - Cloud Monitoring & Logging Strategy

## 1. Overview
This document defines the monitoring and logging infrastructure for OMNIA services running on AWS.

## 2. Log Aggregation (Amazon CloudWatch Logs)
* **Application Logs**: Django container stdout/stderr streams are piped directly to CloudWatch Log Groups.
* **Database Logs**: PostgreSQL query and error logs from AWS RDS are forwarded to `/aws/rds/instance/omnia-db/postgresql`.
* **Retention Policy**: Staging logs retained for 14 days; Production logs retained for 90 days.

## 3. Metrics & Alerting
* **System Metrics**: Monitoring CPU utilization, memory consumption, and storage capacity on container hosts.
* **Database Health**: Monitoring active connections, IOPS, and storage headroom on AWS RDS.
* **Alert Thresholds**:
  * High CPU (> 80% for 5 consecutive minutes) -> Triggers Slack notification.
  * Low Disk Space (< 15% remaining) -> High priority ops alert.
  * HTTP 5xx Error Spikes -> Triggers team notification.

## 4. Incident Response Flow
1. Notification received via CloudWatch Alarm.
2. Cloud & DevOps Owner inspects recent CloudWatch Log streams.
3. If necessary, execute safe service restart or initiate rollback procedure.