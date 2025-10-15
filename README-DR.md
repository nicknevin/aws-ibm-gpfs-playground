# Setting up clusters for DR work.

I have modified the playbooks to support multiple clusters.
Basic usage is to create a cluster config file say config.yaml which contains
settings/overrides for a cluster and specify it with the `-e @config.yaml` option
when running a playbook.

See my example config files dr-cluster1.yaml and dr-cluster2.yaml.
You will want to edit them or use them as template for your own configs.

## Set up

One time initial setup of the OCP clients (oc, kubectl, etc.) per cluster.
```
ansible-playbook -i hosts -e @dr-cluster1.yaml playbooks/ocp-clients.yml
ansible-playbook -i hosts -e @dr-cluster2.yaml playbooks/ocp-clients.yml
```

The playbook dr-setup.yml just creates an OCP cluster, creates a single EBS io2
volume and attaches it to all the worker nodes. There is no set up of GPFS.

To create and setup DR cluster 1.
```
ansible-playbook -i hosts -e @dr-cluster1.yaml playbooks/dr-setup.yml
```
Do similarly for cluster 2.

The playbook dr-ceph.yml sets up ceph on a cluster. It installs ceph and
configures it. This was cribbed from Michele's ceph setup and will definitely
need some tweaking to set up cross cluster replication.

For example on DR cluster 1.
```
ansible-playbook -i hosts -e @dr-cluster1.yaml playbooks/dr-ceph.yml
```

To use oc to interact with the cluster you will want to set KUBECONFIG to point to the relevant file. For example
```
export KUBECONFIG=$HOME/dr-playground/<cluster-name>/ocp_install_files/auth/kubeconfig
```

## Tear down

```
ansible-playbook -i hosts -e @dr-cluster1.yaml playbooks/dr-destroy.yml
ansible-playbook -i hosts -e @dr-cluster2.yaml playbooks/dr-destroy.yml
```
