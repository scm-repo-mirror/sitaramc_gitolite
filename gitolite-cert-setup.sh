#!/bin/bash

# this takes a "default" (well on ubuntu anyway, which is the VM I happen to be
# using) ssh setup, and adds certificate-y stuff to it so you know what needs
# to change to get this going for real.

# TODO: add link to old email, explain non-root, explain constraints

# this would reset everything, but best not to use it
# rm -rf /etc/ssh /home/*/.ssh
# tar xf /snap2.tar

systemctl restart sshd
SYSTEMD_COLORS=yes systemctl status sshd | cat

# ------------------------------------------------------------------------------
# create CA keys first time round

# for now we do this without passphrases on the ca keys
cd /etc/ssh
[[ -f user_ca ]] || {
	set -x
	ssh-keygen -f user_ca -N ""
	ssh-keygen -f host_ca -N ""
	set +x; vifm-pause
}

# ------------------------------------------------------------------------------
# host side

# sign the (already existing) host key
# this is done on each host with **its own** host keys
# for now we only sign the rsa key, ignoring the ecdsa and ed25519 keys
cd /etc/ssh
[[ -f ssh_host_rsa_key-cert.pub ]] || {
	set -x
	ssh-keygen -s host_ca -I CA-server -h -n testpc ssh_host_rsa_key
	ls -al ssh_host_rsa_key-cert.pub
	set +x; vifm-pause
}

# add the following to sshd config

cat <<-EOF > /etc/ssh/sshd_config.d/gitolite.conf
	# make the server "offer" this host-key-certificate when a user tries to login
	HostCertificate /etc/ssh/ssh_host_rsa_key-cert.pub

	# make host trust user certificates
	TrustedUserCAKeys /etc/ssh/user_ca.pub
	# we have only one ca for now, but in real life this file could have
	# multiple ca pubkeys, one per line

	# just for the git user, force command "/glwrapper".  This is a bit
	# kludgy.  You could use "ForceCommand=..." in sshd_config, but you
	# can't specify the authorized principal without using either
	# AuthorizedPrincipalsFile (or AuthorizedPrincipalsCommand)
	Match User gittest
	    # once you have migrated everyone to certs, uncomment this line and
	    # restart sshd
	    AuthorizedKeysFile none

	    # expose auth info: this creates an env var $SSH_USER_AUTH pointing
	    # to a file that contains the certificate used, from which we
	    # extract the gitolite-user
	    ExposeAuthInfo yes

	    AuthorizedPrincipalsFile /gl-apf
	    # /gl-apf contains just one line:
	    #	restrict,command="/gl-wrapper" gitolite
	    # gl-wrapper will parse $SSH_USER_AUTH and extract the gitolite
	    # username from it, then call gitolite-shell
EOF

# restart sshd

systemctl restart sshd
SYSTEMD_COLORS=yes systemctl status sshd | cat

# ------------------------------------------------------------------------------
# user side

# make the "client" accept this CA as a host CA
# this will be the same for every client, since we have only one ca
cd /etc/ssh
(echo -n "@cert-authority testpc "; cat host_ca.pub) > ssh_known_hosts

# and this is how you setup a gitolite user.  You need to give him both the
# generic "gitolite" principal, so that he can be allowed in to the server, and
# also a specific one to identify the person's gitolite username ("alice" in
# this case)
ssh-keygen -s user_ca -I user-1 -n gitolite,gitolite-user:alice /home/gittest/.ssh/u1.pub
ssh-keygen -s user_ca -I user-2 -n gitolite,gitolite-user:carol /home/gittest/.ssh/u2.pub
