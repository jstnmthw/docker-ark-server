#!/usr/bin/env bash

set -e

[[ -z "${DEBUG}" ]] || set -x

function may_update() {
  if [[ "${UPDATE_ON_START}" != "true" ]]; then
    return
  fi

  echo "\$UPDATE_ON_START is 'true'..."

  # 0: No update is available
  if ${ARKMANAGER} checkupdate; then
    echo "...no update available"
    return
  fi

  ${ARKMANAGER} update --force --backup
}

function create_missing_dir() {
  for DIRECTORY in ${@}; do
    [[ -n "${DIRECTORY}" ]] || return
    if [[ ! -d "${DIRECTORY}" ]]; then
      sudo mkdir -p "${DIRECTORY}"
      echo "...successfully created ${DIRECTORY}"
    fi
  done
}

function copy_missing_file() {
  SOURCE="${1}"
  DESTINATION="${2}"

  if [[ ! -f "${DESTINATION}" ]]; then
    sudo cp -a "${SOURCE}" "${DESTINATION}"
    echo "...successfully copied ${SOURCE} to ${DESTINATION}"
  fi
}

if [[ ! "$(id -u "${STEAM_USER}")" -eq "${STEAM_UID}" ]] || [[ ! "$(id -g "${STEAM_GROUP}")" -eq "${STEAM_GID}" ]]; then
  sudo usermod -o -u "${STEAM_UID}" "${STEAM_USER}"
  sudo groupmod -o -g "${STEAM_GID}" "${STEAM_GROUP}"
  sudo chown -R "${STEAM_USER}":"${STEAM_GROUP}" "${ARK_SERVER_VOLUME}" "${STEAM_HOME}"
fi

args=("$*")
if [[ "${ENABLE_CROSSPLAY}" == "true" ]]; then
  args=('--arkopt,-crossplay' "${args[@]}");
fi
if [[ "${DISABLE_BATTLEYE}" == "true" ]]; then
  args=('--arkopt,-NoBattlEye' "${args[@]}");
fi

echo "_______________________________________"
echo ""
echo "# Ark Server - $(date)"
echo "# UID ${STEAM_UID} - GID ${STEAM_GID}"
echo "# ARGS ${args[@]}"
echo "_______________________________________"

ARKMANAGER="$(command -v arkmanager)"
[[ -x "${ARKMANAGER}" ]] || (
  echo "Ark manger is missing"
  exit 1
)

cd "${ARK_SERVER_VOLUME}"

echo "Setting up folder and file structure..."
create_missing_dir "${ARK_SERVER_VOLUME}/log" "${ARK_SERVER_VOLUME}/backup" "${ARK_SERVER_VOLUME}/staging" "${ARK_SERVER_VOLUME}/restore"
copy_missing_file "${STEAM_HOME}/crontab" "${ARK_SERVER_VOLUME}/crontab"
copy_missing_file "/s3-backup.sh" "${ARK_SERVER_VOLUME}/s3-backup.sh"

## Need to set correct permissions on the newly created folders? (Tested with Ubuntu)
echo "Setting permissions..."
sudo chown -R "${STEAM_USER}":"${STEAM_GROUP}" "${ARK_SERVER_VOLUME}"
sudo chmod +x "${ARK_SERVER_VOLUME}/s3-backup.sh"

if [[ ! -d ${ARK_SERVER_VOLUME}/server ]] || [[ ! -f ${ARK_SERVER_VOLUME}/server/version.txt ]]; then
  echo "No game files found. Installing..."
  create_missing_dir \
    "${ARK_SERVER_VOLUME}/server/ShooterGame/Saved/SavedArks" \
    "${ARK_SERVER_VOLUME}/server/ShooterGame/Saved/Config/LinuxServer" \
    "${ARK_SERVER_VOLUME}/server/ShooterGame/Content/Mods" \
    "${ARK_SERVER_VOLUME}/server/ShooterGame/Binaries/Linux"
  sudo touch "${ARK_SERVER_VOLUME}/server/ShooterGame/Binaries/Linux/ShooterGameServer"
  sudo chown -R "${STEAM_USER}":"${STEAM_GROUP}" "${ARK_SERVER_VOLUME}/server"
  ${ARKMANAGER} install
  if [[ "${RESTORE_ON_FIRST_LAUNCH}" == "true" ]]; then
    echo "First time launch, attempting to restore from s3..."
    aws s3 cp "${AWS_BUCKET_URL}/main.tar.bz2" "${ARK_SERVER_VOLUME}/restore/"
    if [[ -f "${ARK_SERVER_VOLUME}/restore/main.tar.bz2" ]]; then
      ${ARKMANAGER} restore "${ARK_SERVER_VOLUME}/restore/main.tar.bz2"
    else
      echo "No restore file found."
    fi
  fi
else
  may_update
fi

ACTIVE_CRONS="$(grep -v "^#" "${ARK_SERVER_VOLUME}/crontab" 2>/dev/null | wc -l)"
if [[ ${ACTIVE_CRONS} -gt 0 ]]; then
  echo "Loading crontab..."
  sudo touch "${ARK_SERVER_VOLUME}/environment"
  sudo chown -R "${STEAM_USER}":"${STEAM_GROUP}" "${ARK_SERVER_VOLUME}/environment"
  declare -p | grep -E 'SERVER_MAP|STEAM_HOME|STEAM_USER|ARK_SERVER_VOLUME|GAME_CLIENT_PORT|SERVER_LIST_PORT|RCON_PORT|UPDATE_ON_START|PRE_UPDATE_BACKUP|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_DEFAULT_REGION|AWS_BUCKET_URL' > "${ARK_SERVER_VOLUME}/environment"
  crontab "${ARK_SERVER_VOLUME}/crontab"
  sudo cron -f &
  echo "...done"
else
  echo "No crontab set"
fi

exec ${ARKMANAGER} run "${args[@]}"
