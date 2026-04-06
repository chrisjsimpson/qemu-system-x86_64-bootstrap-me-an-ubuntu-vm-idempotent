#!/bin/bash

###
# Bootstrap and run a qemu powered Ubuntu VM with SSH enabled and qemu monitor
# accessible in an idempotent way. Useful for quickly verifying projects in an
# isolated way locally or within a runner.
#
# Usage:
# ./doit.sh
# Will download, configure and run a fresh ubuntu VM and print ssh access to
# the screen once booted. Assumes kvm with fallback to tcg if KVM not
# present (which will be very slow).
#
# Originally written for
# Validation of server-bootstrap repo (https://github.com/KarmaComputing/server-bootstrap)
# (does it do what it claims?)
#
# Method of verification:
# - Create Ubuntu VM to contain the verification environment 
#   (using qemu-system-x86_64)
# - Within the cleanly bootstrapped VM (qemu-system-x86_64), checkout, buid and run
#   according to all instructions within the server-bootstrap repo.
#   This includes (but not limited to):
#   - Building of an ipxe iso (build-ipxe-iso.sh)
#   - Building of an alpine image (build-alpine.sh)
#   - 'Run the stack' (needs definition) see:
#     https://github.com/KarmaComputing/server-bootstrap/blob/93748cb4468a252351f0e7ad761ad8b8225d490e/repo-server-bootstrap-ncl-issue-20/README.md
###

set -exuo pipefail

KEEP_VM_RUNNING_AFTER_SCRIPT_EXIT="${1:-notset}"

# Want ping to work within the VM?
# If you’re using QEMU on Linux >= 3.0, it can use unprivileged ICMP ping sockets to allow ping to the Internet. 
# Ref https://www.qemu.org/docs/master/system/devices/net.html#using-the-user-mode-network-stack
# As root:
#echo $(id -u) $(id -u) > /proc/sys/net/ipv4/ping_group_range

function clean_exit() {
  echo Killing python web server if present
  kill $(cat PYTHON_WEB_SERVER_PID)
  echo Killing qemu via QEMU_PID_FILE if present
  kill $(cat QEMU_PID_FILE)
}

# See https://tldp.org/LDP/Bash-Beginners-Guide/html/sect_12_02.html#uponExit

if [[ $KEEP_VM_RUNNING_AFTER_SCRIPT_EXIT != "keep_vm_running_after_script_exit" ]]; then
  trap clean_exit EXIT
fi

echo Checking qemu-system-x86_64 exists
qemu-system-x86_64 --version


FREE_SPACE=$(df -k --output=avail ./ | tail -n1)
# ~5GB for Ubuntu cloud image + 5GB to expand for usable space
NEEDED_SPACE=10000000
    
if [[ $FREE_SPACE -lt $NEEDED_SPACE ]]; then    
  >&2 echo "Not enough free disk space"    
  exit 255
fi; 

if [ ! -f ubuntu-24.04-server-cloudimg-amd64.img ]; then
  wget https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img
  # Keep un-tainted copy of img (cloud-init will edit the disk)
  cp ubuntu-24.04-server-cloudimg-amd64.img ubuntu-24.04-server-cloudimg-amd64.img.original
fi

if [ -f ubuntu-24.04-server-cloudimg-amd64.img ]; then
  echo Overwriting ubuntu-24.04-server-cloudimg-amd64.img to force from new
  cp ubuntu-24.04-server-cloudimg-amd64.img.original ubuntu-24.04-server-cloudimg-amd64.img

  echo Growing image to give at least 5G space
  qemu-img resize ubuntu-24.04-server-cloudimg-amd64.img +5G
fi

echo Generating ssh key for the vm non-interactively

ssh-keygen -N '' -f $(pwd)/dummykey <<< y
PUBLIC_KEY=$(cat dummykey.pub)


# See https://cloudinit.readthedocs.io/en/latest/tutorial/qemu.html
# https://cloudinit.readthedocs.io/en/latest/tutorial/qemu-debugging.html
cat << EOF > user-data
#cloud-config
ssh_pwauth: false
users:
  - name: user1 
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh_authorized_keys:
      - $PUBLIC_KEY
chpasswd:
  expire: False
  users:
  - {name: user1, password: password1, type: text}

disable_root: true

# Commands to run at the end of the cloud-init process
runcmd:
  - systemctl start ssh
EOF

cat << EOF > meta-data
instance-id: someid/somehostname

EOF

touch vendor-data

echo Validating cloud-init data before attempting to use it

cloud-init schema -c user-data

echo Starting python web server in background process to serve user data
python3 -m http.server & PYTHON_WEB_SERVER_PID=$!
echo $PYTHON_WEB_SERVER_PID > ./PYTHON_WEB_SERVER_PID


# See https://www.qemu.org/docs/master/system/invocation.html
# Where did network address 10.0.2.2 come from?
# See:
# https://www.qemu.org/docs/master/system/devices/net.html#using-the-user-mode-network-stack
qemu-system-x86_64 -m 5G \
  -smbios type=1,serial=ds='nocloud;s=http://10.0.2.2:8000/' \
  -cpu host \
  -m 1G \
  -accel kvm -accel tcg \
  -drive file=ubuntu-24.04-server-cloudimg-amd64.img,format=qcow2 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=net0 \
  -serial tcp:127.0.0.1:1234,server=on,wait=off \
  -display none \
  -chardev socket,id=mon1,host=localhost,port=4444,server=on,wait=off \
  -mon chardev=mon1 \
  -pidfile ./QEMU_PID_FILE \
  -daemonize

echo Verifying VM ssh is active and working
for i in {1..15}; do        
  echo retrying ...Verifying VM ssh is active and working
  sleep 3
  set +e
  ssh -o ConnectTimeout=1 -p 2222 -i dummykey user1@127.0.0.1 whoami
  RET_CODE=$?
  if [ $RET_CODE -eq 0 ]; then
    break
  fi
  set -e
done

echo If you want to connect to the *serial* port of the VM
echo it\'s listening on localhost port 1234 connect e.g:
echo nc 127.0.0.1 1234
echo Note, if the VM has finished booting you\'ll see zero output but the VM
echo will be at the login prompt so you can simply type username user1 and
echo password 'password1'.

echo VM is starting, you\'ll be able to ssh into it once booted.
echo To access the Qemu monitor run:
echo nc 127.0.0.1 4444
echo To SSH into the VM run:
echo ssh -p 2222 -i dummykey user1@127.0.0.1
echo If you want to forward ports from your host to your VM guest,
echo '(e.g. A webserver in the VM, and want to access it on your host)'
echo use ssh local forwarding e.g:
echo ssh -p 2222 -L 8001:127.0.0.1:80 -i dummykey user1@127.0.0.1
echo Then visit http://127.0.0.1:8001 in your host web browser.
read -p "Press any key & enter to terminate all"
#wait # use wait if you don't want to use the read above

# Notes
# See 
# https://stackoverflow.com/questions/43235179/how-to-execute-ssh-keygen-without-prompt
# https://stackoverflow.com/questions/7950268/what-does-the-bash-operator-i-e-triple-less-than-sign-mean
