# Polygon on Azure (VMs)

This templated deployment is for Polygon Edge on a 4 node network using traditional IaaS (virtual machines).  This network by default has 4 validators and expose the RPC endpoint via a single load balancer.  The network is private with the public access only via the load balancer for specs ports.

# Template flow

The template includes the follow resources:

- Virtual machine (4)

- Azure Key Vault

- Deployment script

- Load Balancer

- Managed Identity

- Virtual Network

The flow for resource provisioning is as follows:

1. A managed identity will be created that will serve to allow access to the Azure Key Vault from the deployment script and the Virtual Machines.

2. The Azure Key Vault is created that will be used to store assets such as keys and configuration for the nodes.  The managed identity from step 1 will be granted rights to secrets, both read and write.

3. The Deployment Script resource will be created that will leverage the [deploy](../scripts/deploy.sh) script.  This script will generate the keys and configuration for the nodes that will be provisioned in a later step.  These resources will be stored in the Azure Key Vault.

4. The 4 Virtual Machines will be created, based on the size passed as a parameter to the template.

    a. Each Virtual Machine includes a VM extension that uses the [clientDeploy](../scripts/clientDeploy.sh) script.  This script will run after the machine is created and will pull the configuration and keys for itself from the Azure Key Vault, using the Managed Identity provisioned in step 1.

    b. The core process for the validator will then be started using the configuration / keys from the step above.

5.  A single public IP address will be created that will bound to the Azure Load Balancer front end in the next step. 

6.  An Azure Load Balancer will be created that use the Virtual Machines from step 4 as the backend pool.  It will attach the front end to the public IP address.

7.  A single Netwwork Security Group will be created with a single entry for RPC access.  This will be attached to the network to serve for all virtual machines in the network.