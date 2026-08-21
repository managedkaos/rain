#!/bin/bash
set -euo pipefail

# Install Foreman with Puppet 7 on Debian 11 (Bullseye)
# Foreman 3.5 is the last release supporting Bullseye

export DEBIAN_FRONTEND=noninteractive

echo "==> Installing prerequisites..."
apt-get update -y
apt-get install -y ca-certificates wget

echo "==> Removing stale Puppet 6 repositories..."
rm -f /etc/apt/sources.list.d/puppet6.list
rm -f /etc/apt/sources.list.d/puppetlabs-pc1.list

echo "==> Installing Puppet 7 release package..."
wget -q https://apt.puppet.com/puppet7-release-bullseye.deb -O /tmp/puppet7-release-bullseye.deb
dpkg -i /tmp/puppet7-release-bullseye.deb
rm -f /tmp/puppet7-release-bullseye.deb

echo "==> Configuring Foreman 3.5 repository..."
rm -f /etc/apt/sources.list.d/foreman.list
wget -q https://deb.theforeman.org/foreman.asc -O /etc/apt/trusted.gpg.d/foreman.asc
echo "deb https://archivedeb.theforeman.org/ bullseye 3.5" > /etc/apt/sources.list.d/foreman.list
echo "deb https://archivedeb.theforeman.org/ plugins 3.5" >> /etc/apt/sources.list.d/foreman.list

echo "==> Clearing stale APT cache..."
rm -rf /var/lib/apt/lists/partial/*
apt-get clean

echo "==> Updating package lists..."
apt-get update -y

echo "==> Installing Foreman installer..."
apt-get install -y foreman-installer

echo "==> Removing 127.0.1.1 from /etc/hosts (foreman-installer requires hostname to resolve to real IP)..."
sed -i '/^127\.0\.1\.1/d' /etc/hosts

echo "==> Done. Run 'sudo foreman-installer' to complete setup."
