# Copyright (c) 2001-2003 Gregory M. Kurtzer
#
# Copyright (c) 2003-2011, The Regents of the University of California,
# through Lawrence Berkeley National Laboratory (subject to receipt of any
# required approvals from the U.S. Dept. of Energy).  All rights reserved.
#
#
# $Id: HostsFile.pm 50 2010-11-02 01:15:57Z gmk $
#

package Warewulf::Provision::HostsFile;

use Warewulf::Logger;
use Warewulf::Provision::Dhcp;
use Warewulf::DataStore;
use Warewulf::Network;
use Warewulf::SystemFactory;
use Warewulf::Util;
use Warewulf::Include;
use Warewulf::DSOFactory;
use Socket;
use Digest::MD5 qw(md5_hex);


=head1 NAME

Warewulf::Provision::HostsFile - Generate a basic hosts file from the Warewulf
datastore.

=head1 ABOUT


=head1 SYNOPSIS

    use Warewulf::Provision::HostsFile;

    my $obj = Warewulf::Provision::HostsFile->new();
    my $string = $obj->generate();


=head1 METHODS

=over 12
=cut


=item new()

The new constructor will create the object that references configuration the
stores.

=cut
sub
new($$)
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = ();

    $self = {};

    bless($self, $class);

    return $self->init(@_);
}


sub
init()
{
    my $self = shift;

    return($self);
}


=item generate()

This will generate the content of the /etc/hosts file.

=cut
sub
generate()
{
    my $self = shift;
    my $datastore = Warewulf::DataStore->new();
    my $netobj = Warewulf::Network->new();
    my $config = Warewulf::Config->new("provision.conf");
    my $sysconfdir = &wwconfig("sysconfdir");

    my $netdev = $config->get("network device");
    my $ipaddr = $netobj->ipaddr($netdev);
    my $netmask = $netobj->netmask($netdev);
    my $network = $netobj->network($netdev);

    my $hosts;

    if (-f "$sysconfdir/warewulf/hosts-template") {
        open(HOSTS, "$sysconfdir/warewulf/hosts-template");
        while(my $line = <HOSTS>) {
            $hosts .= $line;
        }
        close(HOSTS);
    }

    foreach my $n ($datastore->get_objects("node")->get_list()) {
        my $nodename = $n->get("fqdn") || $n->get("name");
        my $cluster = $n->get("cluster");
        my $domain = $n->get("domain");
        my $master_ipv4_addr = $netobj->ip_unserialize($master_ipv4_bin);
        my $default_name;

        &dprint("Evaluating node: $nodename\n");

        if (! defined($nodename)) {
            next;
        }

        foreach my $d ($n->get("netdevs")) {
            if (ref($d) eq "Warewulf::DSO::Netdev") {
                my ($netdev) = $d->get("name");
                my ($hwaddr) = $d->get("hwaddr");
                my ($ipv4_bin) = $d->get("ipaddr");
                my $ipv4_addr = $netobj->ip_unserialize($ipv4_bin);
                my $node_network = $netobj->calc_network($ipv4_addr, $netmask);
                my $fqdn_eth = $d->get("fqdn");
                my @name_entries;
                my $name_eth;

                if ($fqdn) {
                    $nodename = $fqdn;
                }

                if (($node_network eq $network) and ! defined($default_name)) {
                    $name_eth = $nodename;
                    $default_name = 1;
                } else {
                    $name_eth = "$nodename-$netdev";
                }

                &dprint("Adding a host entry for: $nodename-$netdev\n");

                if (defined($cluster) and defined($domain)) {
                    push(@name_entries, sprintf("%-18s", "$name_eth.$cluster.$domain"));
                }
                if (defined($cluster)) {
                    push(@name_entries, sprintf("%-18s", "$name_eth.$cluster"));
                } else {
                    push(@name_entries, sprintf("%-18s", $name_eth));
                }
                if (defined($domain)) {
                    push(@name_entries, sprintf("%-18s", "$name_eth.$domain"));
                }

                if ($nodename and $ipv4_addr and $hwaddr) {
                    $hosts .= sprintf("%-23s %s\n", $ipv4_addr, join(" ", @name_entries));
                }

            } else {
                &eprint("Node '$nodename' has an invalid netdevs entry!\n");
            }
        }
    }

    return($hosts);
}


=item update_datastore()

Update the Warewulf datastore with the current hosts file.

=cut
sub
update_datastore()
{
    my $self = shift;
    my $name = "dynamic_hosts";
    my $datastore = Warewulf::DataStore->new();

    &dprint("Updating datastore\n");

    my $hosts = $self->generate();
    my $len = length($hosts);

    &dprint("Getting file object for '$name'\n");
    my $fileobj = $datastore->get_objects("file", "name", $name)->get_object(0);

    if (! $fileobj) {
        $fileobj = Warewulf::DSOFactory->new("file");
        $fileobj->set("name", $name);
    }

    my $binstore = $datastore->binstore($fileobj->get("id"));

    $fileobj->set("checksum", md5_hex($hosts));
    $fileobj->set("path", "/etc/hosts");
    $fileobj->set("format", "data");
    $fileobj->set("length", $len);
    $fileobj->set("uid", "0");
    $fileobj->set("gid", "0");
    $fileobj->set("mode", "0644");

    $datastore->persist($fileobj);

    my $read_length = 0;
    while($read_length != $len) {
        my $buffer = substr($hosts, $read_length, $datastore->chunk_size());
        $binstore->put_chunk($buffer);
        $read_length = length($buffer);
    }

}


=back

=head1 SEE ALSO

Warewulf::Provision::Dhcp

=head1 COPYRIGHT

Copyright (c) 2001-2003 Gregory M. Kurtzer

Copyright (c) 2003-2011, The Regents of the University of California,
through Lawrence Berkeley National Laboratory (subject to receipt of any
required approvals from the U.S. Dept. of Energy).  All rights reserved.

=cut


1;
