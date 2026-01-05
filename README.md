# Quickly Bootstrap a fresh Ubuntu VM using qemu with SSH & monitor access in idempotent way

Bootstrap and run a qemu powered Ubuntu VM with SSH enabled and qemu monitor
accessible in an idempotent way. Useful for quickly verifying projects in an
isolated way locally or within a runner.

## Usage

```bash
./doit.sh
```
Will download, configure and run a fresh ubuntu VM and print ssh access to
the screen once booted. Assumes kvm with fallback to tcg if KVM not
present (which will be very slow).


```
Originally written for
Validation of server-bootstrap repo (https://github.com/KarmaComputing/server-bootstrap)
(does it do what it claims?)

Method of verification:
- Create Ubuntu VM to contain the verification environment 
  (using qemu-system-x86_64)
- Within the cleanly bootstrapped VM (qemu-system-x86_64), checkout, buid and run
  according to all instructions within the server-bootstrap repo.
  This includes (but not limited to):
  - Building of an ipxe iso (build-ipxe-iso.sh)
  - Building of an alpine image (build-alpine.sh)
  - 'Run the stack' (needs definition) see:
    https://github.com/KarmaComputing/server-bootstrap/blob/93748cb4468a252351f0e7ad761ad8b8225d490e/repo-server-bootstrap-ncl-issue-20/README.md
```
