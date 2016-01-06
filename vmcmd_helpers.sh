show_vmcmd_help() {
	echo "Usage:
${0} [vmname...]

    Possible VMs are: ${vbox_names[@]}"
	exit 1
}

vmcmd_vmnames=()
validate_vmcmd_args() {
	while [ $# -gt 0 ];
	do
		case ${1} in
		-h|--help)
			show_vmcmd_help;
			shift;;
		-*)
			show_vmcmd_help;
			msg_err "invalid option: $1"
			;;
		*)	# everything else are vm names
			vmcmd_vmnames+=("$1")
			shift;;
		esac;
	done

	if [ "${#vmcmd_vmnames}" -eq 0 ]; then
		vmcmd_vmnames="${vbox_names[@]}"
	fi
}
