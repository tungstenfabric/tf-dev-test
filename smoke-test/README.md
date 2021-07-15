# Smoke test for a TF deployment 

Very basic test cases to quickly check a deployment.

Note, for now only OpenStack deployments is supported.

### OpenStack deployments test:
- create network
- create subnet
- create security group and security group rule
- create flavor
- run VM
- detect linklocal IP and check that it is working
