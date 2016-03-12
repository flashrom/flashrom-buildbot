export LC_ALL=C
export TZ=UTC0

msg_err () {
	echo "$@. Aborting." >&2
	exit 1
}

msg_warn () {
	echo "$@. Continuing anyway." >&2
}

check_arg () {
	if [ $# -ne 2 -o -z "$2" ] || [[ "$2" == -* ]]; then
		msg_err "Missing argument for $1"
	fi
}

# To distinguish VMs we started (in start_vbox_vm()) remember the VMs that were already running before starting them
declare -A vms_were_running

# stores a mapping of vbox VM names and their IP addresses
declare -A vbox_ips
declare -A vbox_hostonlyifs
declare -A name_vboxes

fill_vbox_arrs() {
	for ck in "${!available_compilers[@]}"; do
		local vmname=${vbox_names[$ck]}
		[ -z "$vmname" ] && continue
		if ! vminfo=$(vboxmanage showvminfo "${vmname}" --machinereadable) 2>/dev/null; then
			msg_warn "There is no VM named $vmname registered on this system"
			return
		fi
		local hostonlyif=$(echo "$vminfo" | grep -oP '(?<=hostonlyadapter2=")[^"]+')
		if [ -z "$hostonlyif" ]; then
			msg_warn "$ck does not seem to have an associated hostonlyif"
			return
		fi
		local vmip=$(VBoxManage list hostonlyifs | grep -ozP "(?s)Name: +${hostonlyif}\s.*?IPAddress:\N*" | grep -ozP "(?<=IPAddress:       )[0-9.]+")
		vmip=${vmip%.1}.2
		if ! valid_ip "$vmip" ; then
			msg_warn "Could not retrieve IP for $ck correctly (got $vmip)"
			return
		fi
		vbox_ips["$ck"]=$vmip
		vbox_hostonlyifs["$ck"]=$hostonlyif
		name_vboxes["$vmname"]="$ck"
	done
}

# This code is based on one from Linux Journal June 26, 2008 
valid_ip() {
	local ip=$1

	# Check the IP address under test to see if it matches the extended REGEX
	regex="^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"
	if [[ ! $ip =~ $regex ]] ; then
		return 1
	fi
	oifs=$IFS
	IFS='.'
	for num in $ip ; do
		if [ $num -gt 255 ]; then
			IFS=$oifs
			return 1
		fi
	done
	IFS=$oifs
	return 0
}

# checks if parameter is an element in an array. invocation example: is_in "gcc" "${available_compilers[@]}"
is_in () {
	arr=$1
	shift
	for elem in "$@"; do
		[[ "$elem" == "$arr" ]] && return 0;
	done
	return 1
}

# checks if parameter is a key in an associative array. invocation example: is_key_in "dos" "$(declare -p available_compilers)"
is_key_in () {
	key="$1"
	eval "local -A arr="${2#*=} # deserialize and eliminate old name/assignment
	test -n "${arr[$key]}"
}

# checks if parameter is element in an associative array and returns the key in the 3rd variable.
# invocation example: get_key_from_name "i586-pc-msdosdjgpp-gcc" "$(declare -p available_compilers)" "ret_val"
get_key_from_name () {
	name="$1"
	eval "local -A arr="${2#*=} # deserialize and eliminate old name/assignment
	for key in "${!arr[@]}"; do
		if [ "${arr["$key"]}" = "$name" ]; then
			eval "$3="$key""
			return 0
		fi
	done
	return 1
}

# get the compiler name from the vm name
# invocation example: get_ck_from_vmname debian-8-amd64 vmname
get_ck_from_vmname () {
	_vmname="$1"
	_var_name="$2"
	eval "$_var_name=${name_vboxes[$_vmname]}"
}

# get the compiler name and the vm name from either of the two
# invocation example: get_ck_and_vmname debian-8-amd64 namevar keyvar
get_ck_and_vmname () {
	local _ck
	local _vmname
	_namevar="$2"
	_keyvar="$3"
	_ck=${name_vboxes[$1]}
	if [ -n "$_ck" ] ; then
		_vmname="$1"
	else
		_vmname=${vbox_names[$1]}
		if [ -n "$_vmname" ] ; then
			_ck="$1"
		else
			msg_err "Could not find a VM matching $1"
		fi
	fi
	eval "$_namevar=$_vmname ; $_keyvar=$_ck"
}

# get the haltcmd_from the vm name
# invocation example: get_haltcmd_from_vmname debian-8-amd64 haltcmd
get_haltcmd_from_vmname () {
	vmname="$1"
	var_name="$2"
	local _vmhaltcmd=${halt_cmds[$vmname]}
	# default to halt -p
	if [ -z "$_vmhaltcmd" ]; then
		_vmhaltcmd="halt -p"
	fi
	eval "$var_name='$_vmhaltcmd'"
}

# ssh_vbox_vm <vm name> [ <user name> [<cmd>] ]
ssh_vbox_vm () {
	local vmname
	local ck
	get_ck_and_vmname "$1" "vmname" "ck"
	local vm_user
	[ -n "$2" ] && vm_user="$2@"
	local vmip=${vbox_ips[$ck]}
	[ -n "$vmip" ] || msg_err "Could not find IP for compiler $ck"
	ssh ${vm_user}${vmip} "$3"
}

# start_vbox_vm [vmname|ck]
start_vbox_vm () {
	local vmname
	local ck
	get_ck_and_vmname "$1" "vmname" "ck"
	local vmip=${vbox_ips[$ck]}

	# set deadline depending on curent VM state:
	#  - 10 secs if the VM is already running (assuming that it is already pretty much ready)
	#  - 50 secs if the VM is saved and needs to be resumed
	#  - 6 mins if the VM needs to boot completely
	local deadline
	if VBoxManage list runningvms | grep -q "${vmname}" ; then
		vms_were_running[$ck]=1
		echo "${vmname} VM is already running."
		deadline=$(date -d 10secs +%s)
	else
		local state=$(vboxmanage showvminfo "${vmname}" --machinereadable | grep -oP '(?<=State=").*(?=")')
		if [ "$state" == "saved" ]; then
			deadline=$(date -d 50secs +%s)
		else
			deadline=$(date -d 6mins +%s)
		fi
		VBoxHeadless --startvm "${vmname}" --vrde off >/dev/null &
	fi

	until ssh ${vm_user}@${vmip} true >/dev/null 2>&1; do
		if [ $(date +%s) -ge ${deadline} ]; then
			echo "No ssh connection within timeout, aborting"
			return 1
		fi
		echo "Waiting for ${vmname} VM to get reachable (for $((${deadline}-$(date +%s))) more secs)..."
		sleep 3
	done
	echo "${vmname} VM started and waiting for commands."
}

shutdown_vm () {
	local vmname="$1"
	if ! VBoxManage list runningvms | grep -q "${vmname}" ; then
		echo "VM ${vmname} is not running."
		continue
	fi

	local vmhaltcmd
	get_haltcmd_from_vmname "${vmname}" "vmhaltcmd"

	[ -z "${vmhaltcmd}" ] && msg_warn "Could not get halt command for VM ${vmname}"
	printf "Executing '$vmhaltcmd' on VM '$vmname'...\n"
	ssh_vbox_vm "${vmname}" root "${vmhaltcmd}"
}
