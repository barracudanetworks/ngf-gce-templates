#!/bin/bash

# initialize logging
. /etc/phion/bin/cloud-logapi.sh
init_log box_Control_daemon gcp-ha

declare -r ROUTE_UPDATE_RETRIES=10

function update_route {
	local -r name=$1
	local -r dest_range=$2
	local -r network=$3
	local -r priority=$4
	local -r other_name=$5
	local -r this_name=$6
	local -r this_zone=$7

	created_route_desc_string="route $name: $dest_range via ${this_name} (${this_zone}) in network $network with priority $priority"
	route_list=$(gcloud compute routes list --filter="name:${name} AND destRange:${dest_range} AND nextHopInstance:${this_zone}/instances/${this_name} AND network:${network} AND priority:${priority}" 2>/dev/null)
	if [[ "_${route_list}" != "_" ]];
	then
		ilog "$created_route_desc_string is set"
		return 0
	fi

	gcloud compute routes describe $name &>/dev/null
	[[ $? == 0 ]] && {
		deleted_route_desc_string="route $name: $dest_range via ${other_name} in network $network with priority $priority"
		gcloud -q compute routes delete $name &>/dev/null
		[[ $? != 0 ]] && {
			elog "error deleting $deleted_route_desc_string"
			return 1
		}
		ilog "deleted route $deleted_route_desc_string"
	}

	gcloud compute routes describe $name &>/dev/null
	[[ $? != 0 ]] && {
		gcloud compute routes create $name --destination-range=$dest_range --next-hop-instance=${this_name} --next-hop-instance-zone=${this_zone} --network=$network --priority=$priority &>/dev/null
		[[ $? != 0 ]] && {
			elog "error creating $created_route_desc_string"
			return 1
		}
		ilog "created $created_route_desc_string"
	}
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

other_instance_name=$(gcloud compute instances list --filter="networkInterfaces.networkIP:${other_instance_mgmt_ip} AND networkInterfaces.network:${vpc_name}" --format="value(name)" 2>/dev/null)

gcloud compute routes list --filter="nextHopInstance:${other_instance_name}" --format="value(name,destRange,network,priority)" 2>/dev/null | while read -r name dest_range network priority; do
	echo "route $name: $dest_range via ${other_name} in network $network with priority $priority"
	tried_update=0
	route_updated=0
	while [ $tried_update -lt $ROUTE_UPDATE_RETRIES ]
	do
		if update_route $name $dest_range $network $priority $other_instance_name $this_instance_name $this_instance_zone;
		then
			tried_update+=1
			sleep 1
			continue
		fi
		route_updated=1
	done
	[[ ! $route_updated ]] && {
		elog "error updating route $name: $dest_range via ${other_name} in network $network with priority $priority"
	}
done

exit 0
