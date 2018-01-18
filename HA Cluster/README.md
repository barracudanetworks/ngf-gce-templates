### Barracuda NextGen Firewall HA Cluster

This Deployment Manager template deploys a cluster of 2 Barracuda NextGen Firewall (NGF) instances into new VPCs in 2 different availability zones of Google Cloud.

## How to deploy
1. Clone the repository to your workstation (or cloud shell). Actually just the sample-deploy.yaml file is enough provided you change the imports[0].path to include full URL of the main template in GitHub.
2. Change the parameters to meet your requirements
3. Deploy a preview:
`gcloud deployment-manager deployments create my-deployment --config sample-deploy.yaml --preview`
4. If everything looks fine, deploy it:
`gcloud deployment-manager deployments update my-deployment`

So far, further steps include:
1. Increasing NIC number and configuring secondary NIC in NGF
2. Setting up static IPs on both NGF instances
3. Creating DHA box on primary instance
4. Copying the PAR file to build the cluster
5. enabling TCP:447 probes from 169.254.269.254 to service public IP
