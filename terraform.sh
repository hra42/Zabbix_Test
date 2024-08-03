#bin/bash
# Author: Henry Rausch
# Version: 1.0
# GitHub: https://github.com/hra42
# Date: 02.08.2024
# Description: This script is used to make the use of the terraform docker image easier
# It will run the docker image with the current directory mounted as /terraform

# Pull the latest terraform image
docker pull hashicorp/terraform:latest

# Check if TF_VAR_hcloud_token is already set in the environment
if [ -z "$TF_VAR_hcloud_token" ]; then
    # If not set in environment, check if hcloud_token exists in auto.tfvars file
    if [ -f "hetzner_token.auto.tfvars" ]; then
        hcloud_token=$(grep -oP 'hcloud_token\s*=\s*"\K[^"]+' hetzner_token.auto.tfvars)
        if [ -n "$hcloud_token" ]; then
            export TF_VAR_hcloud_token="$hcloud_token"
        else
            echo "hcloud_token not found in hetzner_token.auto.tfvars file."
            echo "Please provide your Hetzner Cloud API token:"
            read -s TF_VAR_hcloud_token
            export TF_VAR_hcloud_token
        fi
    else
        echo "hetzner_token.auto.tfvars file not found and TF_VAR_hcloud_token not set in environment."
        echo "Please provide your Hetzner Cloud API token:"
        read -s TF_VAR_hcloud_token
        export TF_VAR_hcloud_token
    fi
fi

# Allow the user to override the default script with init, plan, apply, or destroy
if [ "$1" == "init" ]; then
    docker run --rm -v ${PWD}:/terraform -w /terraform hashicorp/terraform:latest init
elif [ "$1" == "plan" ]; then
    docker run --rm -v ${PWD}:/terraform -w /terraform -e TF_VAR_hcloud_token hashicorp/terraform:latest plan -out=tfplan
elif [ "$1" == "apply" ]; then
    docker run --rm -v ${PWD}:/terraform -w /terraform hashicorp/terraform:latest apply tfplan
elif [ "$1" == "destroy" ]; then
    docker run --rm -v ${PWD}:/terraform -w /terraform -e TF_VAR_hcloud_token hashicorp/terraform:latest destroy --auto-approve
else
    docker run --rm -v ${PWD}:/terraform -w /terraform hashicorp/terraform:latest init && \
    docker run --rm -v ${PWD}:/terraform -w /terraform -e TF_VAR_hcloud_token hashicorp/terraform:latest plan -out=tfplan && \
    docker run --rm -v ${PWD}:/terraform -w /terraform hashicorp/terraform:latest apply tfplan
fi

# Clean up the tfplan file
rm -f tfplan

# Exit with the exit code of the last command
exit $?
