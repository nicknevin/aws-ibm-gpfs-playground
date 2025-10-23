# DR Clusters Setup in Europe - Complete Guide

This document provides a comprehensive guide for setting up and managing Disaster Recovery (DR) clusters in the European region using AWS and OpenShift.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Cluster Configuration](#cluster-configuration)
4. [Setup Procedures](#setup-procedures)
5. [Access Methods](#access-methods)
6. [Monitoring Options](#monitoring-options)
7. [Operational Procedures](#operational-procedures)
8. [Troubleshooting](#troubleshooting)

## Overview

This setup creates two OpenShift DR clusters in the EU North region (Stockholm, Sweden) for disaster recovery purposes:

- **DR Cluster 1**: `dr-eun1b-1` 
- **DR Cluster 2**: `dr-eun1b-2`

Both clusters are configured with:
- OpenShift 4.19.15
- 3 master/worker nodes (m5.4xlarge instances)
- EBS io2 volumes for persistent storage
- Located in `eu-north-1b` availability zone

## Prerequisites

### Required Software
- Ansible 2.18+
- Python 3.13+ with kubernetes library
- AWS CLI configured with appropriate permissions
- OpenShift CLI tools (oc, kubectl)
- htpasswd utility

### AWS Requirements
- AWS account with sufficient permissions
- Default AWS profile configured
- EC2, VPC, and IAM permissions for cluster creation
- EBS volume creation permissions

### Installation Commands
```bash
# Install Python kubernetes library
pip3 install kubernetes

# Install htpasswd (if not available)
sudo dnf install httpd-tools  # Fedora/RHEL
# or
sudo apt-get install apache2-utils  # Ubuntu/Debian
```

## Cluster Configuration

### Configuration Files

#### dr-eun1b-cluster1.yaml
```yaml
ocp_version: "4.19.15"
ocp_az: eu-north-1b
ocp_region: eu-north-1
ocp_domain: fusionaccess.devcluster.openshift.com
ocp_cluster_name: dr-eun1b-1
ocp_worker_count: 0
ocp_master_type: m5.4xlarge
ebs_volume_name: "{{ ocp_cluster_name }}-volume-1"
ssh_pubkey: "{{ lookup('file', '~/.ssh/id_rsa.pub' | expanduser) }}"
basefolder: "{{ '~/dr-playground' | expanduser }}/{{ ocp_cluster_name }}"
templatefolder: "{{ basefolder }}/templates"
```

#### dr-eun1b-cluster2.yaml
```yaml
ocp_version: "4.19.15"
ocp_az: eu-north-1b
ocp_region: eu-north-1
ocp_domain: fusionaccess.devcluster.openshift.com
ocp_cluster_name: dr-eun1b-2
ocp_worker_count: 0
ocp_master_type: m5.4xlarge
ebs_volume_name: "{{ ocp_cluster_name }}-volume-1"
ssh_pubkey: "{{ lookup('file', '~/.ssh/id_rsa.pub' | expanduser) }}"
basefolder: "{{ '~/dr-playground' | expanduser }}/{{ ocp_cluster_name }}"
templatefolder: "{{ basefolder }}/templates"
```

## Setup Procedures

### Step 1: Initial Setup

1. **Clone the repository and navigate to the directory:**
   ```bash
   cd /home/nlevanon/workspace/DR/aws-ibm-gpfs-playground
   ```

2. **Set up OCP clients for both clusters:**
   ```bash
   ansible-playbook -i hosts -e @dr-eun1b-cluster1.yaml playbooks/ocp-clients.yml
   ansible-playbook -i hosts -e @dr-eun1b-cluster2.yaml playbooks/ocp-clients.yml
   ```

### Step 2: Create DR Clusters

1. **Create DR Cluster 1:**
   ```bash
   ansible-playbook -i hosts -e @dr-eun1b-cluster1.yaml playbooks/dr-setup.yml
   ```

2. **Create DR Cluster 2:**
   ```bash
   ansible-playbook -i hosts -e @dr-eun1b-cluster2.yaml playbooks/dr-setup.yml
   ```

### Step 3: Set up Ceph Storage (Optional)

1. **Install Ceph on Cluster 1:**
   ```bash
   ansible-playbook -i hosts -e @dr-eun1b-cluster1.yaml playbooks/dr-ceph.yml
   ```

2. **Install Ceph on Cluster 2:**
   ```bash
   ansible-playbook -i hosts -e @dr-eun1b-cluster2.yaml playbooks/dr-ceph.yml
   ```

## Access Methods

### 1. Command Line Access

#### Using oc/kubectl CLI

**For DR Cluster 1:**
```bash
export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig
~/dr-playground/dr-eun1b-1/4.19.15/oc get nodes
```

**For DR Cluster 2:**
```bash
export KUBECONFIG=~/dr-playground/dr-eun1b-2/ocp_install_files/auth/kubeconfig
~/dr-playground/dr-eun1b-2/4.19.15/oc get nodes
```

#### Using k9s (Terminal UI)

1. **Install k9s:**
   ```bash
   curl -sS https://webinstall.dev/k9s | bash
   ```

2. **Access clusters:**
   ```bash
   # Cluster 1
   export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig
   k9s
   
   # Cluster 2
   export KUBECONFIG=~/dr-playground/dr-eun1b-2/ocp_install_files/auth/kubeconfig
   k9s
   ```

### 2. Web Console Access

**Cluster 1 Console:**
- URL: `https://console-openshift-console.apps.dr-eun1b-1.fusionaccess.devcluster.openshift.com`
- Username: `kubeadmin`
- Password: `cat ~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeadmin-password`

**Cluster 2 Console:**
- URL: `https://console-openshift-console.apps.dr-eun1b-2.fusionaccess.devcluster.openshift.com`
- Username: `kubeadmin`
- Password: `cat ~/dr-playground/dr-eun1b-2/ocp_install_files/auth/kubeadmin-password`

## Monitoring Options

### 1. Built-in OpenShift Monitoring

#### Access Prometheus
```bash
# Cluster 1
export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig
~/dr-playground/dr-eun1b-1/4.19.15/oc get route prometheus-k8s -n openshift-monitoring

# Cluster 2
export KUBECONFIG=~/dr-playground/dr-eun1b-2/ocp_install_files/auth/kubeconfig
~/dr-playground/dr-eun1b-2/4.19.15/oc get route prometheus-k8s -n openshift-monitoring
```

#### Access Grafana
```bash
# Get Grafana route
oc get route grafana -n openshift-monitoring
```

### 2. Cluster Health Monitoring

#### Check Cluster Status
```bash
# Check all nodes
oc get nodes -o wide

# Check cluster operators
oc get clusteroperators

# Check cluster version
oc get clusterversion

# Check pod status across all namespaces
oc get pods --all-namespaces | grep -v Running
```

#### Resource Monitoring
```bash
# Check resource usage
oc top nodes
oc top pods --all-namespaces

# Check persistent volumes
oc get pv
oc get pvc --all-namespaces
```

### 3. AWS CloudWatch Integration

#### Enable CloudWatch Container Insights
```bash
# Install CloudWatch agent
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cloudwatch-namespace.yaml

# Apply CloudWatch configuration
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-daemonset.yaml
```

### 4. Custom Monitoring Setup

#### Install Prometheus Operator
```bash
# Create monitoring namespace
oc new-project monitoring

# Install Prometheus operator
oc apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml
```

#### Set up AlertManager
```bash
# Create AlertManager configuration
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: alertmanager-main
  namespace: openshift-monitoring
data:
  alertmanager.yml: |
    global:
      smtp_smarthost: 'localhost:587'
      smtp_from: 'alertmanager@example.com'
    route:
      group_by: ['alertname']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 1h
      receiver: 'web.hook'
    receivers:
    - name: 'web.hook'
      webhook_configs:
      - url: 'http://127.0.0.1:5001/'
EOF
```

## Operational Procedures

### 1. Backup Procedures

#### Cluster Configuration Backup
```bash
# Backup cluster configuration
oc get --export -o yaml all > cluster-backup-$(date +%Y%m%d).yaml

# Backup secrets
oc get secrets --all-namespaces -o yaml > secrets-backup-$(date +%Y%m%d).yaml

# Backup configmaps
oc get configmaps --all-namespaces -o yaml > configmaps-backup-$(date +%Y%m%d).yaml
```

#### EBS Volume Snapshots
```bash
# Create snapshots of EBS volumes
aws ec2 create-snapshot --volume-id vol-xxxxxxxx --description "DR Cluster Backup $(date)"
```

### 2. Disaster Recovery Procedures

#### Failover Process
1. **Identify primary cluster failure**
2. **Switch DNS/load balancer to secondary cluster**
3. **Restore data from backups**
4. **Validate application functionality**
5. **Update monitoring and alerting**

#### Cross-Cluster Replication Setup
```bash
# Install Velero for cross-cluster backup
oc new-project velero
oc apply -f https://raw.githubusercontent.com/vmware-tanzu/velero/main/examples/openshift/00-velero-install.yaml
```

### 3. Maintenance Procedures

#### Cluster Updates
```bash
# Check available updates
oc get clusterversion

# Apply updates
oc patch clusterversion version --type='merge' -p='{"spec":{"channel":"stable-4.19"}}'
```

#### Node Maintenance
```bash
# Drain node before maintenance
oc adm drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Mark node as unschedulable
oc adm cordon <node-name>

# After maintenance, mark as schedulable
oc adm uncordon <node-name>
```

## Troubleshooting

### Common Issues

#### 1. Cluster Installation Failures
```bash
# Check installation logs
tail -f ~/dr-playground/dr-eun1b-1/ocp_install_files/.openshift_install.log

# Check AWS resources
aws ec2 describe-instances --region eu-north-1 --filters "Name=tag:Name,Values=*dr-eun1b-1*"
```

#### 2. Node Issues
```bash
# Check node status
oc describe node <node-name>

# Check node logs
oc logs -n openshift-machine-config-operator <pod-name>
```

#### 3. Storage Issues
```bash
# Check EBS volume attachments
aws ec2 describe-volumes --region eu-north-1 --filters "Name=tag:Name,Values=*dr-eun1b-1*"

# Check persistent volumes
oc get pv
oc describe pv <pv-name>
```

#### 4. Network Issues
```bash
# Check cluster network
oc get network
oc describe network cluster

# Check DNS resolution
oc get pods -n openshift-dns
```

### Log Locations

- **Installation logs**: `~/dr-playground/dr-eun1b-1/ocp_install_files/.openshift_install.log`
- **Cluster logs**: Access via `oc logs` commands
- **System logs**: Check AWS CloudWatch logs

### Support Contacts

- **AWS Support**: Through AWS Console
- **Red Hat Support**: Through Red Hat Customer Portal
- **Internal Support**: Contact your platform team

## Cleanup Procedures

### Destroy Clusters
```bash
# Destroy DR Cluster 1
ansible-playbook -i hosts -e @dr-eun1b-cluster1.yaml playbooks/dr-destroy.yml

# Destroy DR Cluster 2
ansible-playbook -i hosts -e @dr-eun1b-cluster2.yaml playbooks/dr-destroy.yml
```

### Manual Cleanup
```bash
# Delete EBS volumes
aws ec2 delete-volume --volume-id vol-xxxxxxxx --region eu-north-1

# Delete security groups
aws ec2 delete-security-group --group-id sg-xxxxxxxx --region eu-north-1

# Delete VPC and subnets
aws ec2 delete-subnet --subnet-id subnet-xxxxxxxx --region eu-north-1
aws ec2 delete-vpc --vpc-id vpc-xxxxxxxx --region eu-north-1
```

## Security Considerations

### 1. Access Control
- Use RBAC for fine-grained permissions
- Implement network policies for pod-to-pod communication
- Enable audit logging

### 2. Data Protection
- Encrypt EBS volumes at rest
- Use encrypted communication (TLS/SSL)
- Implement backup encryption

### 3. Compliance
- Follow GDPR requirements for EU data
- Implement data retention policies
- Maintain audit trails

## Cost Optimization

### 1. Resource Right-sizing
- Monitor actual resource usage
- Adjust instance types based on needs
- Use spot instances for non-critical workloads

### 2. Storage Optimization
- Use appropriate EBS volume types
- Implement lifecycle policies
- Regular cleanup of unused resources

---

## Quick Reference

### Cluster Information
- **Region**: eu-north-1 (Stockholm, Sweden)
- **AZ**: eu-north-1b
- **Instance Type**: m5.4xlarge
- **OpenShift Version**: 4.19.15

### Key Commands
```bash
# Switch between clusters
export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig  # Cluster 1
export KUBECONFIG=~/dr-playground/dr-eun1b-2/ocp_install_files/auth/kubeconfig  # Cluster 2

# Check cluster status
oc get nodes -o wide
oc get clusteroperators
oc get clusterversion
```

### Important URLs
- **Cluster 1 Console**: `https://console-openshift-console.apps.dr-eun1b-1.fusionaccess.devcluster.openshift.com`
- **Cluster 2 Console**: `https://console-openshift-console.apps.dr-eun1b-2.fusionaccess.devcluster.openshift.com`

---

*Last Updated: October 23, 2025*
*Version: 1.0*
