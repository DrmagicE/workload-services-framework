#!/bin/bash -e

copy_template () {
    echo copy template $1 to $2
    mkdir -p "$2" || true
    cp -rL $3 "$1"/* "$2"/
}

destroy () {
    trap - SIGINT SIGKILL ERR EXIT
    set +e

    if [[ "$stages" = *"--stage=cleanup"* ]]; then
        if [ -r cleanup.yaml ]; then
            echo "Restore SUT settings..."
            run_playbook cleanup.yaml >> cleanup.logs 2>&1
        fi

        echo "Destroy SUT resources..."
        TF_LOG=ERROR terraform destroy -auto-approve -input=false -no-color -parallelism=1 >> cleanup.logs 2>&1
    fi 

    rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup tfplan .ssh .netrc
    exit ${1:-3}
}

locate_trace_modules () {
    trace_modules=()
    for tp in /opt/workload/template/ansible/traces/roles/* /opt/template/ansible/traces/roles/*; do
        tn="${tp/*\//}"
        if [ -d "$tp" ] && [[ " $@ " = *" --$tn "* ]]; then
            trace_modules+=("$tp")
        fi
    done
    trace_modules_options="$(echo ${trace_modules[@]/*\//} | tr ' ' ',')"
    if [ -n "$trace_modules_options" ]; then
        trace_modules_options="--wl_trace_modules=$trace_modules_options"
    fi
}

run_playbook () {
    options=""
    while [[ "$1" = "-"* ]]; do
      options="$options $1"
      shift
    done
    playbook=$1
    shift

    playbooks=($(awk '/import_playbook/{print gensub("/[^/]+$","",1,$NF)}' $playbook))
    for pb in "${playbooks[@]}"; do
        [ -d "/opt/$pb" ] && copy_template "/opt/$pb" "$pb"
        # patch trace roles
        for tp in "${trace_modules[@]}"; do
            copy_template "$tp" "${tp/*\/template/template}"
        done
        [ -d "/opt/workload/$pb" ] && copy_template "/opt/workload/$pb" "$pb" "-S .origin -b"
    done
    [ "$playbook" = "cluster.yaml" ] && [[ "$stages" != *"--stage=provision"* ]] && return
    cp -f /opt/template/ansible/ansible.cfg .
    ANSIBLE_FORKS=$(nproc) ANSIBLE_ROLES_PATH="$ANSIBLE_ROLES_PATH:template/ansible/common/roles:template/ansible/traces/roles" ansible-playbook $options -i inventory.yaml --private-key "$keyfile" $playbook
}

DIR="$(dirname "$0")"
cd /opt/workspace

stages="$@"
if [[ "$stages" != *"--stage="* ]]; then
    stages="--stage=provision --stage=validation --stage=cleanup"
fi
    
tf_pathes=($(grep -E 'source\s*=.*/template/terraform/' terraform-config.tf | cut -f2 -d'"'))
if [ ${#tf_pathes[@]} -ge 1 ]; then
    keyfile="ssh_access.key"
else
    keyfile="$HOME/.ssh/id_rsa"
fi

if [[ "$stages" = *"--stage=provision"* ]]; then
    echo "Create the provisioning plan..."

    # copy shared stack templates
    if [ -d "$STACK_TEMPLATE_PATH" ]; then
        cp -r -f "${STACK_TEMPLATE_PATH}" "${STACK_TEMPLATE_PATH/*\/template/template}"
    fi

    # copy templates over
    for tfp in "${tf_pathes[@]}"; do
        if [ -d "/opt/workload/template/terraform" ]; then
            copy_template "/opt/workload/$tfp" "$tfp"
        elif [ -d "/opt/$tfp" ]; then
            copy_template "/opt/$tfp" "$tfp"
        else
            echo "Missing $tfp"
            exit 3
        fi
    done
    
    # Create SG white list
    if [ ${#tf_pathes[@]} -ge 1 ]; then
        "$DIR"/get-ip-list.sh /opt/etc/proxy-ip-list.txt > proxy-ip-list.txt
        # Create key pair
        ssh-keygen -m PEM -q -f $keyfile -t rsa -N ''
    fi
    # provision VMs
    terraform init -input=false -no-color -upgrade

    (
        set +e
        retries="$(echo "x $@" | sed -n '/--provision_retries=/{s/.* --provision_retries=\([0-9]*\).*/\1/;p}')"
        delay="$(echo "x $@" | sed -n '/--provision_delay=/{s/.* --provision_delay=\([0-9]*\).*/\1/;p}')"

        sts=1
        for i in $(seq 1 ${retries:-1}); do 
            [ $i -ne 1 ] && echo "Provision Retry: $i..."

            terraform plan -input=false -out tfplan -no-color
            sts=$?
            [ $sts -ne 0 ] && break

            terraform apply -input=false --auto-approve -no-color tfplan
            sts=$?
            [ $sts -eq 0 ] && break

            TF_LOG=ERROR terraform destroy -auto-approve -input=false -no-color -parallelism=1
            echo "Provision delay ${delay:-10}s..."
            sleep ${delay:-10}s
        done
        [ $sts -eq 0 ] || exit $sts
    )

    trap destroy SIGINT SIGKILL ERR EXIT
    terraform show -json > tfplan.json
fi

# create cluster with ansible
# for validation only, we still want to prepare cluster.yaml but not execute it.
locate_trace_modules $@
cat tfplan.json | $DIR/create-cluster.py $@ $trace_modules_options
run_playbook -vv cluster.yaml $@

if [[ "$stages" = *"--stage=validation"* ]]; then
    # create deployment with ansible
    echo "Create the deployment plan..."

    trap destroy SIGINT SIGKILL ERR EXIT

    locate_trace_modules $@
    cat tfplan.json | $DIR/create-deployment.py $@ $trace_modules_options
    run_playbook -vv deployment.yaml $@

    if [ -n "$(ls -1 itr-*/kpi.sh 2> /dev/null)" ]; then
        for publisher in "$DIR"/publish-*.py; do
            publisher="${publisher#*publish-}"
            publisher="${publisher%.py}"
            # create KPI and publish KPI
            if [[ "$@" = *"--${publisher}_publish"* ]]; then
                cat tfplan.json | ($DIR/publish-$publisher.py $@ || true)
            fi
        done
    fi
fi

if [[ "$stages" = *"--stage=cleanup"* ]]; then
    destroy 0
fi

trap - SIGINT SIGKILL ERR EXIT
echo "exit with status: 0"
exit 0
