#! /bin/bash

handle_vbox_vm ()
{
	cmd=$1
	vmname=$2
	vmip=$3
	vmhaltcmd=$4

	case "${cmd}" in
		start)
			VBoxManage list runningvms|grep -q ${vmname} && {
				echo "${vmname} VM is already running. Nothing done."
				return 0
			}
			VBoxHeadless --startvm ${vmname} --vrde off &
			until ssh compiler@${vmip} true >/dev/null 2>&1; do
				echo "Waiting for ${vmname} VM to start..."
				sleep 5
			done
			echo "${vmname} VM started and waiting for commands."
			;;
		stop)
			VBoxManage list runningvms|grep -q ${vmname} || {
				echo "${vmname} VM is already stopped. Nothing done."
				return 0
			}
			ssh root@${vmip} ${vmhaltcmd} >/dev/null 2>&1
			while ping -c 1 ${vmip} >/dev/null 2>&1; do
				echo "Waiting for ${vmname} VM to get disconnected..."
				sleep 5
			done
			while VBoxManage list runningvms|grep -q ${vmname}; do
				echo "Waiting for ${vmname} VM to stop..."
				sleep 5
			done
			chmod 660 "/home/flashrom-buildbot/VirtualBox VMs/${vmname}/${vmname}.vbox"
			echo "${vmname} VM stopped."
			;;
		*)
			echo "Usage: $0 {start|stop}"
			exit 1
			;;
	esac
}
