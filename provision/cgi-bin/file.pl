#!/usr/bin/perl
#
# Copyright (c) 2001-2003 Gregory M. Kurtzer
#
# Copyright (c) 2003-2011, The Regents of the University of California,
# through Lawrence Berkeley National Laboratory (subject to receipt of any
# required approvals from the U.S. Dept. of Energy).  All rights reserved.
#


use CGI;
use Warewulf::DataStore;
use Warewulf::DSOFactory;

my $q = CGI->new();
my $db = Warewulf::DataStore->new();

print $q->header("text/plain");

my $hwaddr = $q->param('hwaddr');
my $fileid = $q->param('fileid');


if (! $fileid) {
    if ($hwaddr =~ /^([a-zA-Z0-9:]+)$/) {
        $hwaddr = $1;

        my $nodeSet = $db->get_objects("node", "hwaddr", $hwaddr);
        my $node = $nodeSet->get_object(0);

        if ($node) {
            my $nodeName = $node->get("name");

            foreach my $file ($node->get("file")) {
                if (! $file) {
                    next;
                }
                my $objSet = $db->get_objects("file", "name", $file);
                foreach my $obj ($objSet->get_list()) {
                    if ($obj) {
                        printf("%s %s %s %s %s %s\n",
                            $obj->get("id") || "NULL",
                            $obj->get("name") || "NULL",
                            $obj->get("uid") || "0",
                            $obj->get("gid") || "0",
                            $obj->get("mode") || "0000",
                            $obj->get("path") || "NULL");
                    }
                }
            }
        }
    }
} elsif ($fileid =~ /^([0-9]+)$/ ) {
    $fileid = $1;
    my $fileObj = $db->get_objects("file", "id", $fileid)->get_object(0);;

    if ($fileObj) {
        my $binstore = $db->binstore($fileObj->get("id"));
        while(my $buffer = $binstore->get_chunk()) {
            print $buffer;
        }
    }

} else {
    &wprint("FILEID contains illegal characters\n");
}