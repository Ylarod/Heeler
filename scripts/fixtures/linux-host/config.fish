# sshd runs every exec through `fish -c`, and fish reads this file first even
# when it is not interactive. The noise on both streams is deliberate: the
# Changes script must find its own framed output around a chatty login shell.
echo "heeler-linux-host: fish login noise on stdout"
echo "heeler-linux-host: fish login noise on stderr" >&2
