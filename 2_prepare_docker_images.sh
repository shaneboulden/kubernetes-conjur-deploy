#!/bin/bash 
set -euo pipefail

. utils.sh

: "${SEEDFETCHER_IMAGE:=cyberark/dap-seedfetcher}"

main() {
  if [[ "${PLATFORM}" = "openshift" ]]; then
    set +x
    podman login -u _ -p $(oc whoami -t) $DOCKER_REGISTRY_PATH --tls-verify=false
    set -x
  fi

  if [[ $CONJUR_DEPLOYMENT == oss ]]; then
    echo "Prepare Conjur OSS cluster"
    prepare_conjur_oss_cluster
  else
    echo "Prepare DAP cluster"
    prepare_conjur_appliance_image
    prepare_seed_fetcher_image
  fi

  if [[ "${DEPLOY_MASTER_CLUSTER}" = "true" ]]; then
    prepare_conjur_cli_image
  fi

  echo "Docker images pushed."
}

prepare_conjur_appliance_image() {
  announce "Tagging and pushing Conjur appliance"

  conjur_appliance_image=$(platform_image conjur-appliance)

  # Try to pull the image if we can
  podman pull $CONJUR_APPLIANCE_IMAGE --tls-verify=false || true
  podman tag $CONJUR_APPLIANCE_IMAGE $conjur_appliance_image

  if [ ! is_minienv ] || [ "${DEV}" = "false" ] ; then
    podman push $conjur_appliance_image --tls-verify=false
  fi
}

prepare_conjur_cli_image() {
  announce "Pulling and pushing Conjur CLI image."

  podman pull cyberark/conjur-cli:$CONJUR_VERSION-latest --tls-verify=false
  podman tag cyberark/conjur-cli:$CONJUR_VERSION-latest conjur-cli:$CONJUR_NAMESPACE_NAME

  cli_app_image=$(platform_image conjur-cli)
  podman tag conjur-cli:$CONJUR_NAMESPACE_NAME $cli_app_image

  if [ ! is_minienv ] || [ "${DEV}" = "false" ]; then
    podman push $cli_app_image --tls-verify=false
  fi
}

prepare_seed_fetcher_image() {
  announce "Pulling and pushing seed-fetcher image."

  podman pull $SEEDFETCHER_IMAGE --tls-verify=false

  seedfetcher_image=$(platform_image seed-fetcher)
  podman tag $SEEDFETCHER_IMAGE $seedfetcher_image

  if [ ! is_minienv ] || [ "${DEV}" = "false" ]; then
    podman push $seedfetcher_image --tls-verify=false
  fi
}

prepare_conjur_oss_cluster() {
  announce "Pulling and pushing Conjur OSS image."

  # Allow using local conjur images for deployment
  conjur_oss_src_image="${LOCAL_CONJUR_IMAGE:-}"
  if [[ -z "$conjur_oss_src_image" ]]; then
    conjur_oss_src_image="cyberark/conjur:latest"
    podman pull $conjur_oss_src_image --tls-verify=false
  fi

  conjur_oss_dest_image=$(platform_image "conjur")
  echo "Tagging Conjur image $conjur_oss_src_image as $conjur_oss_dest_image"
  podman tag "$conjur_oss_src_image" "$conjur_oss_dest_image"

  if [ "${DEV}" = "false" ]; then
    echo "Pushing Conjur image ${conjur_oss_dest_image} to repo..."
    podman push "$conjur_oss_dest_image" --tls-verify=false
  fi

  announce "Pulling and pushing Nginx image."

  nginx_image=$(platform_image "nginx")
  # Push nginx image to openshift repo
  pushd oss/nginx_base
    sed -i -e "s#{{ CONJUR_NAMESPACE_NAME }}#$CONJUR_NAMESPACE_NAME#g" ./proxy/ssl.conf
    podman build -t $nginx_image .

    if [ "${DEV}" = "false" ]; then
      podman push $nginx_image --tls-verify=false
    fi
  popd
}

main $@
