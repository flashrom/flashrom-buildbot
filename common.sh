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

# stores a mapping of vbox VM names and their IP addresses
declare -A vbox_ips
declare -A vbox_hostonlyifs

fill_vbox_ips() {
	for ck in "${!available_compilers[@]}"; do
		local vmname=${vbox_names[$ck]}
		[ -z "$vmname" ] && continue
		if ! vminfo=$(vboxmanage showvminfo "${vmname}" --machinereadable) 2>/dev/null; then
			msg_err "There is no VM named $vmname registered on this system"
		fi
		local hostonlyif=$(echo "$vminfo" | grep -oP '(?<=hostonlyadapter2=")[^"]+')
		local vmip=$(VBoxManage list hostonlyifs | grep -ozP "(?s)Name: +${hostonlyif}\s.*?IPAddress:\N*" | grep -ozP "(?<=IPAddress:       )[0-9.]+")
		vmip=${vmip%.1}.2
		if ! valid_ip "$vmip" ; then
			msg_err "Could not retrieve IP for $ck correctly (got $vmip)"
		fi
		vbox_ips["$ck"]=$vmip
		vbox_hostonlyifs["$ck"]=$hostonlyif
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
#invocation example: get_ck_from_vmname debian-8-amd64 vmname
get_ck_from_vmname () {
	vmname="$1"
	var_name="$2"
	get_key_from_name "$vmname" "$(declare -p vbox_names)" "$var_name"
}
