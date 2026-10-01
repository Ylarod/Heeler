# A Linux Host for the Changes field verification (#395).
#
# The merge gate only exercises macOS git under POSIX sh. This image gives the
# same Changes reads a Debian git and two login shells: fish, which re-parses
# whatever sshd hands its -c option, and Debian's POSIX /bin/sh (dash). It is
# driven by scripts/verify-changes-linux-host.sh; nothing in CI builds it.
#
# The base is pinned by digest so every run starts from the same userland;
# bookworm resolves git 2.39 and fish 3.6.
FROM debian:bookworm@sha256:9344f8b8992482f80cba753f323adeaf17690076c095ccff6cc9536be98185dc

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-server git fish \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd \
    && rm -f /etc/ssh/ssh_host_*

# Two accounts that differ only in their login shell. `*` leaves the password
# unusable without locking the account, so public key logins still work.
RUN useradd --create-home --shell /usr/bin/fish heelerfish \
    && useradd --create-home --shell /bin/sh heelersh \
    && usermod --password '*' heelerfish \
    && usermod --password '*' heelersh

COPY --chown=heelerfish:heelerfish config.fish /home/heelerfish/.config/fish/config.fish
COPY sshd_config /etc/ssh/sshd_config.heeler
COPY entrypoint.sh /usr/local/bin/heeler-linux-host

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/heeler-linux-host"]
