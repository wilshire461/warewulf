#
# Copyright (c) 2001-2003 Gregory M. Kurtzer
#
# Copyright (c) 2003-2011, The Regents of the University of California,
# through Lawrence Berkeley National Laboratory (subject to receipt of any
# required approvals from the U.S. Dept. of Energy).  All rights reserved.
#




package Warewulf::Module::Cli::Provision;

use Getopt::Long;
use Text::ParseWords;
use Warewulf::DataStore;
use Warewulf::Logger;
use Warewulf::File;
use Warewulf::Module::Cli;
use Warewulf::Provision;
use Warewulf::Term;
use Warewulf::Util;

our @ISA = ('Warewulf::Module::Cli');

my $entity_type = "node";

sub
new()
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};

    bless($self, $class);

    $self->init();

    return $self;
}

sub
init()
{
    my ($self) = @_;

    $self->{"DB"} = Warewulf::DataStore->new();
}

sub
keyword()
{
    return("provision");
}

sub
help()
{
    my $h;

    $h .= "USAGE:\n";
    $h .= "     provision <command> [options] [targets]\n";
    $h .= "\n";
    $h .= "SUMMARY:\n";
    $h .= "    The provision command is used for setting node provisioning attributes.\n";
    $h .= "\n";
    $h .= "COMMANDS:\n";
    $h .= "\n";
    $h .= "         set             Modify an existing node configuration\n";
    $h .= "         list            List a summary of the node(s) provision configuration\n";
    $h .= "         print           Print the full node(s) provision configuration\n";
    $h .= "         help            Show usage information\n";
    $h .= "\n";
    $h .= "TARGETS:\n";
    $h .= "\n";
    $h .= "     The target is the specification for the node you wish to act on. All targets\n";
    $h .= "     can be bracket expanded as follows:\n";
    $h .= "\n";
    $h .= "         n00[0-99]       inclusively all nodes from n0000 to n0099\n";
    $h .= "         n00[00,10-99]   n0000 and inclusively all nodes from n0010 to n0099\n";
    $h .= "\n";
    $h .= "OPTIONS:\n";
    $h .= "\n";
    $h .= "     -l, --lookup        How should we reference this node? (default is name)\n";
    $h .= "     -b, --bootstrap     Define the bootstrap image that this node should use\n";
    $h .= "     -v, --vnfs          Define the VNFS that this node should use\n";
# TODO: Master and bootserver are not used yet...
#    $h .= "         --master        Specifically set the Warewulf master(s) for this node\n";
#    $h .= "         --bootserver    If you have multiple DHCP/TFTP servers, which should be\n";
#    $h .= "                         used to boot this node\n";
    $h .= "         --files         Define the files that should be provisioned to this node\n";
    $h .= "         --fileadd       Add a file to be provisioned to this node\n";
    $h .= "         --filedel       Remove a file to be provisioned to this node\n";
    $h .= "         --preshell      Start a shell on the node before provisioning (boolean)\n";
    $h .= "         --postshell     Start a shell on the node after provisioning (boolean)\n";
    $h .= "         --bootlocal     Boot the node from the local disk (do not provision)\n";
    $h .= "         --kargs         Define the kernel arguments (assumes \"quiet\" if UNDEF)\n";
    $h .= "\n";
    $h .= "EXAMPLES:\n";
    $h .= "\n";
    $h .= "     Warewulf> provision set n000[0-4] --bootstrap=2.6.30-12.x86_64\n";
    $h .= "     Warewulf> provision set n00[00-99] --fileadd=ifcfg-eth0\n";
    $h .= "     Warewulf> provision set -l=cluster mycluster --vnfs=rhel-6.0\n";
    $h .= "     Warewulf> provision set -l=group mygroup hello group123\n";
    $h .= "     Warewulf> provision set n00[0-4] --kargs=\"console=ttyS0,57600 quiet\"\n";
    $h .= "     Warewulf> provision list n00[00-99]\n";
    $h .= "\n";

    return($h);
}

sub
summary()
{
    my $output;

    $output .= "Node provision manipulation commands";

    return($output);
}


sub
complete()
{
    my $self = shift;
    my $db = $self->{"DB"};
    my $opt_lookup = "name";
    my @ret;

    if (! $db) {
        return();
    }

    @ARGV = ();

    foreach (&quotewords('\s+', 0, @_)) {
        if (defined($_)) {
            push(@ARGV, $_);
        }
    }

    Getopt::Long::Configure ("bundling", "passthrough");

    GetOptions(
        'l|lookup=s'    => \$opt_lookup,
    );

    if (exists($ARGV[1]) and ($ARGV[1] eq "print" or $ARGV[1] eq "set")) {
        @ret = $db->get_lookups($entity_type, $opt_lookup);
    } else {
        @ret = ("list", "set", "print");
    }

    @ARGV = ();

    return(@ret);
}

sub
exec()
{
    my $self = shift;
    my $db = $self->{"DB"};
    my $term = Warewulf::Term->new();
    my $opt_lookup = "name";
    my $opt_bootstrap;
    my $opt_vnfs;
    my $opt_preshell;
    my $opt_postshell;
    my $opt_bootlocal;
    my @opt_master;
    my @opt_bootserver;
    my @opt_files;
    my @opt_fileadd;
    my @opt_filedel;
    my $opt_kargs;
    my $return_count;
    my $objSet;
    my @changes;
    my $command;
    my $persist_bool;
    my $object_count;

    @ARGV = ();
    push(@ARGV, @_);

    Getopt::Long::Configure ("bundling", "nopassthrough");

    GetOptions(
        'files=s'       => \@opt_files,
        'fileadd=s'     => \@opt_fileadd,
        'filedel=s'     => \@opt_filedel,
        'kargs=s'       => \$opt_kargs,
        'master=s'      => \@opt_master,
        'bootserver=s'  => \@opt_bootserver,
        'b|bootstrap=s' => \$opt_bootstrap,
        'v|vnfs=s'      => \$opt_vnfs,
        'preshell=s'    => \$opt_preshell,
        'postshell=s'   => \$opt_postshell,
        'bootlocal=s'   => \$opt_bootlocal,
        'l|lookup=s'    => \$opt_lookup,
    );

    $command = shift(@ARGV);

    if (! $db) {
        &eprint("Database object not avaialble!\n");
        return();
    }

    $objSet = $db->get_objects("node", $opt_lookup, &expand_bracket(@ARGV));
    $object_count = $objSet->count();

    if ($object_count eq 0) {
        &nprint("No nodes found\n");
        return();
    }


    if (! $command) {
        &eprint("You must provide a command!\n\n");
        print $self->help();
    } elsif ($command eq "set") {
        if ($opt_bootstrap) {
            if (uc($opt_bootstrap) eq "UNDEF") {
                foreach my $obj ($objSet->get_list()) {
                    my $name = $obj->name() || "UNDEF";
                    $obj->bootstrapid(undef);
                    &dprint("Deleting bootstrap for node name: $name\n");
                    $persist_bool = 1;
                }
                push(@changes, sprintf("   UNDEF: %-20s\n", "BOOTSTRAP"));
            } else {
                my $bootstrapObj = $db->get_objects("bootstrap", "name", $opt_bootstrap)->get_object(0);
                if ($bootstrapObj and my $bootstrapid = $bootstrapObj->get("_id")) {
                    foreach my $obj ($objSet->get_list()) {
                        my $name = $obj->name() || "UNDEF";
                        $obj->bootstrapid($bootstrapid);
                        &dprint("Setting bootstrapid for node name: $name\n");
                        $persist_bool = 1;
                    }
                    push(@changes, sprintf("     SET: %-20s = %s\n", "BOOTSTRAP", $opt_bootstrap));
                } else {
                    &eprint("No bootstrap named: $opt_bootstrap\n");
                }
            }
        }

        if ($opt_vnfs) {
            if (uc($opt_vnfs) eq "UNDEF") {
                foreach my $obj ($objSet->get_list()) {
                    my $name = $obj->name() || "UNDEF";
                    $obj->vnfsid(undef);
                    &dprint("Deleting vnfsid for node name: $name\n");
                    $persist_bool = 1;
                }
                push(@changes, sprintf("   UNDEF: %-20s\n", "VNFS"));
            } else {
                my $vnfsObj = $db->get_objects("vnfs", "name", $opt_vnfs)->get_object(0);
                if ($vnfsObj and my $vnfsid = $vnfsObj->get("_id")) {
                    foreach my $obj ($objSet->get_list()) {
                        my $name = $obj->name() || "UNDEF";
                        $obj->vnfsid($vnfsid);
                        &dprint("Setting vnfsid for node name: $name\n");
                        $persist_bool = 1;
                    }
                    push(@changes, sprintf("     SET: %-20s = %s\n", "VNFS", $opt_vnfs));
                } else {
                    &eprint("No VNFS named: $opt_vnfs\n");
                }
            }
        }

        if (defined($opt_preshell)) {
            if (uc($opt_preshell) eq "UNDEF" or
                uc($opt_preshell) eq "FALSE" or
                uc($opt_preshell) eq "NO" or
                uc($opt_preshell) eq "N" or
                $opt_preshell == 0
            ) {
                foreach my $obj ($objSet->get_list()) {
                    my $name = $obj->name() || "UNDEF";
                    $obj->preshell(0);
                    &dprint("Disabling preshell for node name: $name\n");
                    $persist_bool = 1;
                }
                push(@changes, sprintf("   UNDEF: %-20s\n", "PRESHELL"));
            } else {
                foreach my $obj ($objSet->get_list()) {
                    my $name = $obj->name() || "UNDEF";
                    $obj->preshell(1);
                    &dprint("Enabling preshell for node name: $name\n");
                    $persist_bool = 1;
                }
                push(@changes, sprintf("     SET: %-20s = %s\n", "PRESHELL", 1));
            }
        }

        if (defined($opt_postshell)) {
            if (uc($opt_postshell) eq "UNDEF" or
                uc($opt_postshell) eq "FALSE" or
                uc($opt_postshell) eq "NO" or
                uc($opt_postshell) eq "N" or
                $opt_postshell == 0
            ) {
                foreach my $obj ($objSet->get_list()) {
                    my $name = $obj->name() || "UNDEF";
                    $obj->postshell(0);
                    &dprint("Disabling postshell for node name: $name\n");
                    $persist_bool = 1;
                }
                push(@changes, sprintf("   UNDEF: %-20s\n", "POSTSHELL"));
            } else {
                foreach my $obj ($objSet->get_list()) {
                    my $name = $obj->name() || "UNDEF";
                    $obj->postshell(1);
                    &dprint("Enabling postshell for node name: $name\n");
                    $persist_bool = 1;
                }
                push(@changes, sprintf("     SET: %-20s = %s\n", "POSTSHELL", 1));
            }
        }

        if (defined($opt_bootlocal)) {
            if (uc($opt_bootlocal) eq "UNDEF" or
                uc($opt_bootlocal) eq "FALSE" or
                uc($opt_bootlocal) eq "NO" or
                uc($opt_bootlocal) eq "N" or
                $opt_bootlocal == 0
            ) {
                foreach my $obj ($objSet->get_list()) {
                    my $name = $obj->name() || "UNDEF";
                    $obj->bootlocal(0);
                    &dprint("Disabling bootlocal for node name: $name\n");
                    $persist_bool = 1;
                }
                push(@changes, sprintf("   UNDEF: %-20s\n", "BOOTLOCAL"));
            } else {
                foreach my $obj ($objSet->get_list()) {
                    my $name = $obj->name() || "UNDEF";
                    $obj->bootlocal(1);
                    &dprint("Enabling bootlocal for node name: $name\n");
                    $persist_bool = 1;
                }
                push(@changes, sprintf("     SET: %-20s = %s\n", "BOOTLOCAL", 1));
            }
        }

        if (@opt_files) {
            my @file_ids;
            my @file_names;
            foreach my $filename (split(",", join(",", @opt_files))) {
                &dprint("Building file ID's for: $filename\n");
                my @objList = $db->get_objects("file", "name", $filename)->get_list();
                if (@objList) {
                    foreach my $fileObj ($db->get_objects("file", "name", $filename)->get_list()) {
                        if ($fileObj->id()) {
                            &dprint("Found ID for $filename: ". $fileObj->id() ."\n");
                            push(@file_names, $fileObj->name());
                            push(@file_ids, $fileObj->id());
                        } else {
                            &eprint("No file ID found for: $filename\n");
                        }
                    }
                } else {
                    &eprint("No file found for name: $filename\n");
                }
            }
            if (@file_ids) {
                foreach my $obj ($objSet->get_list()) {
                    my $name = $obj->name() || "UNDEF";
                    $obj->fileids(@file_ids);
                    &dprint("Setting file IDs for node name: $name\n");
                    $persist_bool = 1;
                }
                push(@changes, sprintf("     SET: %-20s = %s\n", "FILES", join(",", @file_names)));
            }
        }

        if (@opt_fileadd) {
            my @file_ids;
            my @file_names;
            foreach my $filename (split(",", join(",", @opt_fileadd))) {
                &dprint("Building file ID's for: $filename\n");
                my @objList = $db->get_objects("file", "name", $filename)->get_list();
                if (@objList) {
                    foreach my $fileObj ($db->get_objects("file", "name", $filename)->get_list()) {
                        if ($fileObj->id()) {
                            &dprint("Found ID for $filename: ". $fileObj->id() ."\n");
                            push(@file_names, $fileObj->name());
                            push(@file_ids, $fileObj->id());
                        } else {
                            &eprint("No file ID found for: $filename\n");
                        }
                    }
                } else {
                    &eprint("No file found for name: $filename\n");
                }
            }
            if (@file_ids) {
                foreach my $obj ($objSet->get_list()) {
                    my $name = $obj->name() || "UNDEF";
                    $obj->fileidadd(@file_ids);
                    &dprint("Adding file IDs for node name: $name\n");
                    $persist_bool = 1;
                }
                push(@changes, sprintf("     ADD: %-20s = %s\n", "FILES", join(",", @file_names)));
            }
        }

        if (@opt_filedel) {
            my @file_ids;
            my @file_names;
            foreach my $filename (split(",", join(",", @opt_filedel))) {
                &dprint("Building file ID's for: $filename\n");
                my @objList = $db->get_objects("file", "name", $filename)->get_list();
                if (@objList) {
                    foreach my $fileObj ($db->get_objects("file", "name", $filename)->get_list()) {
                        if ($fileObj->id()) {
                            &dprint("Found ID for $filename: ". $fileObj->id() ."\n");
                            push(@file_names, $fileObj->name());
                            push(@file_ids, $fileObj->id());
                        } else {
                            &eprint("No file ID found for: $filename\n");
                        }
                    }
                } else {
                    &eprint("No file found for name: $filename\n");
                }
            }
            if (@file_ids) {
                foreach my $obj ($objSet->get_list()) {
                    my $name = $obj->name() || "UNDEF";
                    $obj->fileiddel(@file_ids);
                    &dprint("Setting file IDs for node name: $name\n");
                    $persist_bool = 1;
                }
                push(@changes, sprintf("     DEL: %-20s = %s\n", "FILES", join(",", @file_names)));
            }
        }

        if ($opt_kargs) {
            $opt_kargs =~ s/\"//g;
            my @kargs = split(/\s+/,$opt_kargs);
            foreach my $k (@kargs) {
                &dprint("Including kernel argument += $k\n");
            }

            foreach my $obj ($objSet->get_list()) {
                my $name = $obj->name() || "UNDEF";
                $obj->kargs(@kargs);
                &dprint("Setting kernel arguments for node name: $name\n");
                $persist_bool = 1;
            }
            if (uc($kargs[0]) eq "UNDEF") {
                push(@changes, sprintf("     DEL: %-20s = %s\n", "KARGS", "[ALL]"));
            } else {
                push(@changes, sprintf("     SET: %-20s = %s\n", "KARGS", '"' . join(" ",@kargs) . '"'));
            }
        }

        if ($persist_bool) {
            if ($command ne "new" and $term->interactive()) {
                print "Are you sure you want to make the following changes to ". $object_count ." node(s):\n\n";
                foreach my $change (@changes) {
                    print $change;
                }
                print "\n";
                my $yesno = lc($term->get_input("Yes/No> ", "no", "yes"));
                if ($yesno ne "y" and $yesno ne "yes") {
                    &nprint("No update performed\n");
                    return();
                }
            }

            $return_count = $db->persist($objSet);

            &iprint("Updated $return_count objects\n");

        }
    } elsif ($command eq "status") {
        &wprint("Persisted status updates (and thus this command) have been deprecated for\n");
        &wprint("scalibility and minimizing DB hits. Each node now logs directly to it's\n");
        &wprint("master's syslog server if it is in listen mode.\n");

    } elsif ($command eq "print") {
        foreach my $o ($objSet->get_list()) {
            my @files;
            my $fileObjSet;
            my $name = $o->name() || "UNDEF";
            my $vnfs = "UNDEF";
            my $bootstrap = "UNDEF";
            if ($o->fileids()) {
                $fileObjSet = $db->get_objects("file", "_id", $o->get("fileids"));
            }
            if ($fileObjSet) {
                foreach my $f ($fileObjSet->get_list()) {
                    push(@files, $f->name());
                }
            } else {
                push(@files, "UNDEF");
            }
            if (my $vnfsid = $o->vnfsid()) {
                my $vnfsObj = $db->get_objects("vnfs", "_id", $vnfsid)->get_object(0);
                if ($vnfsObj) {
                    $vnfs = $vnfsObj->name();
                }
            }
            if (my $bootstrapid = $o->bootstrapid()) {
                my $bootstrapObj = $db->get_objects("bootstrap", "_id", $bootstrapid)->get_object(0);
                if ($bootstrapObj) {
                    $bootstrap = $bootstrapObj->name();
                }
            }
            my $kargs = join(" ",$o->kargs()) || "quiet";

            &nprintf("#### %s %s#\n", $name, "#" x (72 - length($name)));
            printf("%15s: %-16s = %s\n", $name, "BOOTSTRAP", $bootstrap);
            printf("%15s: %-16s = %s\n", $name, "VNFS", $vnfs);
            printf("%15s: %-16s = %s\n", $name, "FILES", join(",", @files));
            printf("%15s: %-16s = %s\n", $name, "PRESHELL", $o->preshell() ? "TRUE" : "FALSE");
            printf("%15s: %-16s = %s\n", $name, "POSTSHELL", $o->postshell() ? "TRUE" : "FALSE");
            printf("%15s: %-16s = \"%s\"\n", $name, "KARGS", $kargs);
            if ($o->get("filesystems")) {
                printf("%15s: %-16s = %s\n", $name, "FILESYSTEMS", join(",", $o->get("filesystems")));
            }
            if ($o->get("diskformat")) {
                printf("%15s: %-16s = %s\n", $name, "DISKFORMAT", join(",", $o->get("diskformat")));
            }
            if ($o->get("diskpartition")) {
                printf("%15s: %-16s = %s\n", $name, "DISKPARTITION", join(",", $o->get("diskpartition")));
            }
            printf("%15s: %-16s = %s\n", $name, "BOOTLOCAL", $o->bootlocal() ? "TRUE" : "FALSE");
        }

    } elsif ($command eq "list") {
        &nprintf("%-19s %-15s %-21s %-21s\n", "NODE", "VNFS", "BOOTSTRAP", "FILES");
        &nprint("================================================================================\n");
        foreach my $o ($objSet->get_list()) {
            my $fileObjSet;
            my @files;
            my $name = $o->name() || "UNDEF";
            my $vnfs = "UNDEF";
            my $bootstrap = "UNDEF";
            if (my @fileids = $o->fileids()) {
                $fileObjSet = $db->get_objects("file", "_id", @fileids);
            }
            if ($fileObjSet) {
                foreach my $f ($fileObjSet->get_list()) {
                    push(@files, $f->name());
                }
            } else {
                push(@files, "UNDEF");
            }
            if (my $vnfsid = $o->vnfsid()) {
                my $vnfsObj = $db->get_objects("vnfs", "_id", $vnfsid)->get_object(0);
                if ($vnfsObj) {
                    $vnfs = $vnfsObj->name();
                }
            }
            if (my $bootstrapid = $o->get("bootstrapid")) {
                my $bootstrapObj = $db->get_objects("bootstrap", "_id", $bootstrapid)->get_object(0);
                if ($bootstrapObj) {
                    $bootstrap = $bootstrapObj->name();
                }
            }
            printf("%-19s %-15s %-21s %-21s\n",
                &ellipsis(19, $name, "end"),
                &ellipsis(15, $vnfs, "end"),
                &ellipsis(21, $bootstrap, "end"),
                &ellipsis(21, join(",", @files), "end")
            );
        }
    } elsif ($command eq "help") {
        print $self->help();

    } else {
        &eprint("Unknown command: $command\n\n");
        print $self->help();
    }

    # We are done with ARGV, and it was internally modified, so lets reset
    @ARGV = ();

    return($return_count);
}


1;
