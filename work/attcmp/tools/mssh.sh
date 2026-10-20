#!/bin/sh
# mssh.sh <remote command>  /  MSCP=1 mssh.sh <scp args...>
export SSH_ASKPASS=/tmp/claude-1000/-home-vboxuser-AeroFgtNeo/560dbddd-2c54-4bd4-b6db-4e3d9472357d/scratchpad/askpass.sh SSH_ASKPASS_REQUIRE=force DISPLAY=:0
O="-o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -o ConnectTimeout=10"
if [ -n "$MSCP" ]; then exec setsid -w scp $O "$@"; fi
exec setsid -w ssh $O root@192.168.1.138 "$@"
