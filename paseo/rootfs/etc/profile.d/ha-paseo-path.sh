# Debian's /etc/profile assigns PATH unconditionally, which wipes the
# directories set via ENV in the image whenever a LOGIN shell starts -- and a
# terminal pane in the Paseo UI is a login shell. Without this, user-installed
# agent updates in /data/home/.npm-global and provider wrappers in
# /share/paseo/bin are invisible from a terminal even though they work fine for
# agents spawned by the daemon.
#
# profile.d is sourced after that assignment, so prepending here wins.

case ":${PATH}:" in
    *":/share/paseo/bin:"*) ;;
    *) PATH="/data/home/.npm-global/bin:/share/paseo/bin:${PATH}"; export PATH ;;
esac
