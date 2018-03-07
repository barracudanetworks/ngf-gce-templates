#!/bin/bash

# initialize logging
. /etc/phion/bin/cloud-logapi.sh
init_log box_Control_daemon gcp-ha

declare -r ROUTE_UPDATE_RETRIES=10
declare -r ROUTE_UPDATE_WAIT_RETRIES=10

function update_route {
	local -r name=$1
	local -r dest_range=$2
	local -r network=$3
	local -r priority=$4
	local -r other_name=$5
	local -r this_name=$6
	local -r this_zone=$7
	local -r tags="${8//;/,}"

	retries=0
	while [ $retries -lt $ROUTE_UPDATE_RETRIES ]
	do
		retries=$((retries + 1))
		created_route_desc_string="route $name: $dest_range via ${this_name} (${this_zone}) in network $network with priority $priority and tags $tags"
		deleted_route_desc_string="route $name: $dest_range via ${other_name} in network $network with priority $priority and tags $tags"

		gcloud -q compute routes delete $name &>/dev/null
		[[ $? != 0 ]] && {
			elog "error deleting $deleted_route_desc_string"
			continue
		}
		ilog "deleted route $deleted_route_desc_string"

		if [ $tags ]; then
			gcloud -q compute routes create $name --destination-range=$dest_range --next-hop-instance=${this_name} --next-hop-instance-zone=${this_zone} --network=$network --priority=$priority --tags="$tags" &>/dev/null
		else
			gcloud -q compute routes create $name --destination-range=$dest_range --next-hop-instance=${this_name} --next-hop-instance-zone=${this_zone} --network=$network --priority=$priority &>/dev/null
		fi
		[[ $? != 0 ]] && {
			elog "error creating $created_route_desc_string"
			continue
		}
		ilog "created $created_route_desc_string"
		break
	done
	return 0
}

[[ $# != 3 ]] && {
	elog "invalid arguments: $@"
	exit 1
}

[[ "_$1" != "_HA-START" ]] && {
	exit 0
}


[[ ! -f "/opt/phion/config/active/boxnetha.conf" && ! -f "/opt/phion/config/active/boxnet.conf" ]] && {
	elog "could not find the  network configuration"
	exit 1
}

project_id=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id 2>/dev/null)

[[ "_$project_id" == "_" ]] && {
	elog "could not find the gcp project name"
	exit 1
}

this_instance_name=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name 2>/dev/null)
this_instance_mgmt_ip=$(boxinfo config /opt/phion/config/active/boxnet.conf boxnet ip 2>/dev/null)
this_instance_zone=$(basename $(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone 2>/dev/null))
for itfIdx in $(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/ 2>/dev/null)
do
	itfIp=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/$itfIdx/ip 2>/dev/null)
	[[ "_$itfIp" == "_$this_instance_mgmt_ip" ]] && {
		vpc_name=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/$itfIdx/network 2>/dev/null)
	}
done

[[ "_$vpc_name" == "_" ]] && {
	elog "could not find the vpc network name"
	exit 1
}
vpc_name=$(basename $vpc_name)

other_instance_mgmt_ip=$(boxinfo config /opt/phion/config/active/boxnetha.conf boxnet ip 2>/dev/null)
[[ "_${other_instance_mgmt_ip}" == "_" ]] && {
	elog "could not find HA partner management IP"
	exit 1
}

other_instance_name_and_zone=( $(gcloud -q compute instances list --filter="networkInterfaces.networkIP=${other_instance_mgmt_ip} AND networkInterfaces.network=${vpc_name}" --format="value(name,zone)" 2>/dev/null) )
other_instance_name=${other_instance_name_and_zone[0]}
other_instance_zone=${other_instance_name_and_zone[1]}

routes_to_update=$(gcloud -q compute routes list --filter="nextHopInstance=https://www.googleapis.com/compute/v1/projects/${project_id}/zones/${other_instance_zone}/instances/${other_instance_name}" --format="value(name,destRange,network,priority,tags)" 2>/dev/null)
if [ -z "$routes_to_update" ]
then
	ilog "no routes to update found"
	exit 0
fi

echo "${routes_to_update}" | while read -r name dest_range network priority tags; do
	update_route $name $dest_range $network $priority $other_instance_name $this_instance_name $this_instance_zone $tags &
done

sleep 30

routes_to_update_array=( $( echo "${routes_to_update}" | awk '{printf "%s\n", $1}') )
number_of_routes_to_update=${#routes_to_update_array[@]}
number_of_routes_updated=0
retries=0
while [ $number_of_routes_to_update -gt $number_of_routes_updated -a $retries -lt $ROUTE_UPDATE_WAIT_RETRIES ]
do
	routes_updated=( $(gcloud -q compute routes list --filter="nextHopInstance=https://www.googleapis.com/compute/v1/projects/${project_id}/zones/${other_instance_zone}/instances/${this_instance_name}" --format="value(name)" 2>/dev/null) )
	number_of_routes_updated=${#routes_updated[@]}
	retries=$(( retries + 1 ))
	sleep 20
done

exit 0
