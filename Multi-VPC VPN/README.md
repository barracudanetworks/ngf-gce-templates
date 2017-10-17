* Barracuda NextGen Firewall - Multi-VPC Connectivity

This solution deploys a new VPC (Hub VPC) and an NGF instance forming an access hub between peered VPCs and external resources.

![Network diagram]()

More information on the architecture can be foundin [Barracuda Campus]().

** How to deploy

1. copy the `sample-deploy.yaml` *configuration* file to your computer
1. modify it to match your configuration
1. deploy using gcloud:
```
gcloud deployment-manager deployments create my-deployment --config sample-deploy.yaml
```
