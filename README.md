# tf-test

tf-test is a tool for testing of Tungsten Fabric deployments by means of various test suites and methods.

Supported test suites are:
- [smoke](https://github.com/tungstenfabric/tf-test/tree/master/smoke-test)
- [contrail-sanity](https://github.com/tungstenfabric/tf-test/tree/master/contrail-sanity)

Generic interface consists of the following environment variables:
- ORCHESTRATOR      - deployment orchestrator: kubernetes (default) or openstack
- OPENSTACK_VERSION - version of OpenStack (default is queens, it is for OpenStack deployments only)
- CONTROLLER_NODES  - list of Contrail Controller nodes (default is the current node - AIO installation)
- AGENT_NODES       - list of Contrail Agent Controller nodes (default is the current node - AIO installation)
- DOMAINSUFFIX      - domain name suffix (by default is detected from the current host)

There might be additional parameters depending on a test.

The project is seemlessly integrated with [tf-devstack](https://github.com/tungstenfabric/tf-devstack/tree/master). So that there is no need to provide parameters as they be consumed automatically.

Example for AIO installation with tf-devstack:

```bash
git clone https://github.com/tungstenfabric/tf-test
git clone https://github.com/tungstenfabric/tf-devstack
./tf-devstack/ansible/run.sh
./tf-test/smoke-test/run.sh
```
