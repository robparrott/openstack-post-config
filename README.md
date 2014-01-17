openstack-post-config
=====================

Set of scripts to configure and create objects in a successfully built OpenStack environment.

For now assumes that

- You run from the root directory of this repo
- that there's a set of auth credentials in one of the following
-- `/root/keystonerc_admin` 
-- `/root/openrc` 
-- `./localrc`
- You are using neutron networking
- You have external HTTP access

## Using

To run the post-config, execute
    bash main.sh

Also include useful functions for clearing out objects in OpenStack.

## Helper Cleanup Functions

To us, `source include/cleanup_function.sh` and then use one of the built in functions to clear out certain objects. For example:

    openstack_purge_subnets myproject

Wil clear out all subnets that have "myproject" in the name. This uses basic grepping functionality, and can take regex's.

For cleaning up after a tempest run, you can use a wrapper script; from the root of this repo, run

    ./bin/cleanup_tempest_objects.sh

Which should clear out all the temp objects from the tempest unit tests.





