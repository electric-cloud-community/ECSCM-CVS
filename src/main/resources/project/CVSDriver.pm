# -------------------------------------------------------------------------
# ECSCM::CVS::Driver
#    CVSDriver.pm
#
# Purpose
#    Object to represent interactions with CVS.
# -------------------------------------------------------------------------

package ECSCM::CVS::Driver;
@ISA = (ECSCM::Base::Driver);

# -------------------------------------------------------------------------
# Includes
# -------------------------------------------------------------------------
use ElectricCommander;
use Time::Local;
use XML::XPath;
use Getopt::Long;
use File::Spec;
use File::Path;
use Cwd;
use warnings;
#use strict;
use HTTP::Date(qw {str2time time2str time2iso time2isoz});
$|=1;

# -------------------------------------------------------------------------
# Constants
# -------------------------------------------------------------------------
use constant {
    SUCCESS => 0,
    ERROR   => 1,
    
    PLUGIN_NAME => 'ECSCM-CVS',
};


if (!defined ECSCM::Base::Driver) {
    require ECSCM::Base::Driver;
}

if (!defined ECSCM::CVS::Cfg) {
    require ECSCM::CVS::Cfg;
}

####################################################################
# Object constructor for ECSCM::CVS::Driver
#
# Arguments:
#    cmdr          previously initialized ElectricCommander handle
#    name          name of this configuration
#
# Returns:
#   new object of CVS Driver
#
####################################################################
sub new {
    my $this = shift;
    my $class = ref($this) || $this;

    my $cmdr = shift;
    my $name = shift;

    my $cfg = new ECSCM::CVS::Cfg($cmdr, "$name");
    if ("$name" ne "") {
        my $sys = $cfg->getSCMPluginName();
        if ("$sys" ne 'ECSCM-CVS') { die 'SCM config $name is not type ECSCM-CVS'; }
    }

    my ($self) = new ECSCM::Base::Driver($cmdr,$cfg);

    bless ($self, $class);
    return $self;
}

####################################################################
# isImplemented - checks wheather a method is implemented or not.
# Arguments:
#    method         Name of the method to check.
#
# Returns:
#   new object of CVS Driver
####################################################################
sub isImplemented {
    my ($self, $method) = @_;
    
    if ($method eq 'getSCMTag' || 
        $method eq 'checkoutCode' || 
        $method eq 'apf_driver' || 
        $method eq 'cpf_driver') {
        return 1;
    } else {
        return 0;
    }
}

####################################################################
# get scm tag for sentry (continuous integration)
####################################################################

####################################################################
# getSCMTag
# 
# Get the latest changelist on this branch/client
#
# Args:
# Return: 
#    changeNumber - a string representing the last change sequence #
#    changeTime   - a time stamp representing the time of last change     
####################################################################
sub getSCMTag {
    my ($self, $opts) = @_;

    # add configuration that is stored for this config
    my $name = $self->getCfg()->getName();
    my %row = $self->getCfg()->getRow($name);
    foreach my $k (keys %row) {
        $self->debug("Reading $k=$row{$k} from config");		
        $opts->{$k}="$row{$k}";
    }

    # Load userName and password from the credential
    ($opts->{cvsUserName}, $opts->{cvsPassword}) = 
        $self->retrieveUserCredential($opts->{credential}, 
        $opts->{cvsUserName}, $opts->{cvsPassword});

    if (length ($opts->{protocol}) == 0) {
        $self->issueWarningMsg ("*** No CVS protocol was specified for\n    $projectName:$scheduleName");
    }
    if (length ($opts->{cvsUserName}) == 0) {
            $self->issueWarningMsg ("*** No CVS user name was specified for\n    $projectName:$scheduleName");
    }
    if (length ($opts->{servername}) == 0) {
            $self->issueWarningMsg ("*** No CVS server name was specified for\n    $projectName:$scheduleName");
    }
    if (length ($opts->{serverpath}) == 0) {
            $self->issueWarningMsg ("*** No CVS server path was specified for\n    $projectName:$scheduleName");
    }
    
    my $here = getcwd();
	
	# login command
    my $cvsRoot = ':' . $opts->{protocol} . ':' . $opts->{cvsUserName} . ':' . $opts->{cvsPassword} . '@' . $opts->{servername} . '/' . $opts->{serverpath};
	
    if (defined ($opts->{dest}) && ("$opts->{dest}" ne "." && "$opts->{dest}" ne "" )) {
        $opts->{dest} = File::Spec->rel2abs($opts->{dest}); 
        if (!-d $opts->{dest}) {		
			mkpath($opts->{dest});			
			if (!chdir $opts->{dest}) {
				print "could not change to directory $opts->{dest}\n";
				exit 1;
			}
			$self->checkoutCode($opts);		
           	chdir $opts->{module};
		} else{
			chdir $opts->{dest};					
			chdir $opts->{module};
			my $cvsUpdate = "cvs -d $cvsRoot update -d";    
			my $ret = "";      
			eval {
			     $ret = `$cvsUpdate 2>&1`;
			};	           		
		}        
    }
	    
    # set the generic cvs command
    my $cvsCommand = "cvs -d $cvsRoot log";    
	my $cmndReturn = "";      
    eval {
        $cmndReturn = `$cvsCommand 2>&1`;
    };
	    
    chdir $here;
    
	my @lines = split(/=+/, $cmndReturn);
	
    my $lastChangeDate = 0;
    my $lastCommitId = 0;
    my $currentDate = 0;
    my $currentCommitId = "";
    my $date = "";
    
    foreach my $line (@lines) 
    {	  
	  if (defined $line) {	    			
			if($line =~ /date: ([\d\-\/\ \:\w]+)/) {
				$date = $1;
				$currentDate = CVSstr2time($date);
				$line =~ /commitid: ([\d\w]+)/;
				$currentCommitId = $1;
          	  			
				if($currentDate > $lastChangeDate) {
					$lastChangeDate = $currentDate;
					$lastCommitId = $currentCommitId;											
				}
			}
		}
    }   
	
    return ($lastCommitId, $lastChangeDate);
}

####################################################################
# checkoutCode
#
# Results:
#   Uses the "cvs checkout" command to checkout code to the workspace.
#   Collects data to call functions to set up the scm change log.
#
# Arguments:
#   self -              the object reference
#   opts -              A reference to the hash with values
#
# Returns
#   Output of the the "cvs checkout" command.
#
####################################################################
sub checkoutCode
{
    my ($self,$opts) = @_;

    if (! (defined $opts->{dest})) {
        warn "dest argument required in checkoutCode";
        return;
    }
    if (! (defined $opts->{module})) {
        warn "module argument required in checkoutCode";
        return;
    }
    if (length ($opts->{protocol}) == 0) {
        $self->issueWarningMsg ("*** No CVS protocol was specified for\n    $projectName:$scheduleName");
    }
    if (length ($opts->{servername}) == 0) {
            $self->issueWarningMsg ("*** No CVS server name was specified for\n    $projectName:$scheduleName");
    }
    if (length ($opts->{serverpath}) == 0) {
            $self->issueWarningMsg ("*** No CVS server path was specified for\n    $projectName:$scheduleName");
    }
    # Load userName and password from the credential
    ($opts->{cvsUserName}, $opts->{cvsPassword}) = 
        $self->retrieveUserCredential($opts->{credential}, 
        $opts->{cvsUserName}, $opts->{cvsPassword});
    
    if (length ($opts->{cvsUserName}) == 0) {
        $self->issueWarningMsg ("*** No CVS user name was specified for\n    $projectName:$scheduleName");
    }
    
    my $here = getcwd();

    if (defined ($opts->{dest}) && ("$opts->{dest}" ne "." && "$opts->{dest}" ne "" )) {
        $opts->{dest} = File::Spec->rel2abs($opts->{dest});
        print "Changing to directory $opts->{dest}\n";
        mkpath($opts->{dest});
        if (!chdir $opts->{dest}) {
            print "could not change to directory $opts->{dest}\n";
            exit 1;
        }
    }
    # login command
    my $cvsRoot = ':' . $opts->{protocol} . ':' . $opts->{cvsUserName} . ':' . $opts->{cvsPassword} . '@' . $opts->{servername} . ':/' . $opts->{serverpath};
    my $cvsLogin = "cvs -d $cvsRoot login";
    
    # run CVS
    my $cmndReturn = $self->RunCommand("$cvsLogin");
    
    # cvs -d :pserver:user@192.168.127.130:/cvsrepo checkout examples
    #Remove password from command. It won't be needed.
    #$cvsRoot = ':' . $opts->{protocol} . ':' . $opts->{cvsUserName} . '@' . $opts->{servername} . ':/' . $opts->{serverpath};
    
	my $command= "cvs ";
	
	if($opts->{run_quietly} && $opts->{run_quietly} ne "")
	{
		$command .= "-Q "
	}
	
	if($opts->{revision} && $opts->{revision} ne "")
	{
		$command .= "-d $cvsRoot checkout -r $opts->{revision} $opts->{module}";
	}
	else
	{
		$command .= "-d $cvsRoot checkout $opts->{module}";
	}

    print "CVS Command: $command \n";
	
	#This runs the command and prints the output into the log file if neccesary
	qx{$command}; 
    
    chdir $here;
        
    return $result;
}

#-------------------------------------------------------------------
# agent preflight functions
#-------------------------------------------------------------------

###############################################################################
# apf_getScmInfo
#
#       If the client script passed some SCM-specific information, then it is
#       collected here.#
# Results:
#   Uses the "svn checkout" command to checkout code to the workspace.
#   Collects data to call functions to set up the scm change log.
#
# Arguments:
#   self -              the object reference
#   opts -              A reference to the hash with values
#
# Returns
#   Output of the the "svn checkout" command.
###############################################################################
sub apf_getScmInfo
{
    my ($self,$opts) = @_;
        
    my $scmInfo = $self->pf_readFile("ecpreflight_data/scmInfo");
    $scmInfo =~ m/(.*)\n(.*)\n(.*)\n(.*)/;
    $opts->{scm_cvsroot} = $1;
    $opts->{scm_lastchange} = $2;
    $opts->{module} = $3;
    $opts->{scm_workdir} = $4;
    
    
    print("CVS information received from client:\n"
            . "CVS Root: $opts->{scm_workdir}\n"
            . "Last change: $opts->{scm_lastchange}\n"
            . "Module: $opts->{module}\n\n");
}

###############################################################################
# apf_createSnapshot
#
#       Create the basic source snapshot before overlaying the deltas passed
#       from the client.
###############################################################################

sub apf_createSnapshot
{
    my ($self,$opts) = @_;   
    $self->checkoutCode($opts);
}

###############################################################################
# driver
#
#       Main program for the application.
###############################################################################

sub apf_driver()
{
    my ($self,$opts) = @_;
    print "Running agent preflight driver.\n";
    if ($opts->{test}) { $self->setTestMode(1); }
    $opts->{delta} = "ecpreflight_files";  
       
    $self->apf_downloadFiles($opts);
    $self->apf_transmitTargetInfo($opts);
    $self->apf_getScmInfo($opts);
      
    $self->apf_createSnapshot($opts);
        
    my $dir = File::Spec->catdir($opts->{dest},$opts->{module});     
    $opts->{dest} = $dir;    
    $self->apf_deleteFiles($opts);
    $self->apf_overlayDeltas($opts); 
}


#-------------------------------------------------------------------
# client preflight file
#-------------------------------------------------------------------

###############################################################################
# cpf_cvs
#
#       Runs an svn command.  Also used for testing, where the requests and
#       responses may be pre-arranged.
###############################################################################
sub cpf_cvs {
    my ($self,$opts, $command, $options) = @_;
    
    $self->cpf_debug("Running CVS command \"$command\"");
    if ($opts->{opt_Testing}) {
        my $request = uc("cvs_$command");
        $request =~ s/[^\w]//g;
        if (defined($ENV{$request})) {
            return $ENV{$request};
        } else {
            $self->cpf_error("Pre-arranged command output not found in ENV");
        }
    } else {
        return $self->RunCommand("cvs $command", $options);
    }
}

###############################################################################
# copyDeltas
#
#       Finds all new and modified files, and calls putFiles to upload them
#       to the server.
###############################################################################
sub cpf_copyDeltas()
{
    my ($self,$opts) = @_;
    $self->cpf_display("Collecting delta information");

    $self->cpf_saveScmInfo($opts,$opts->{scm_cvsroot} ."\n"
            . $opts->{scm_lastchange} ."\n"
            . $opts->{scm_module} ."\n"
            . $opts->{scm_workdir} ."\n");      
            

    $self->cpf_findTargetDirectory($opts);
    $self->cpf_createManifestFiles($opts);
    
    my $here = getcwd();
        
    if (defined ($opts->{scm_workdir}) && ("$opts->{scm_workdir}" ne "." && "$opts->{scm_workdir}" ne "" )) {
        #$opts->{dest} = File::Spec->rel2abs($opts->{scm_workdir});
        $self->cpf_debug ("Changing to directory $opts->{scm_workdir}\n");
        mkpath($opts->{scm_workdir});
        if (!chdir $opts->{scm_workdir}) {
           $self->cpf_debug("could not change to directory $opts->{scm_workdir}\n");
            exit 1;
        }
    }

    # Collect a list of opened files.
    my $out = "";
    my $command = "cvs -d $opts->{scm_cvsroot} -qn update";   
    eval {
        $out = `$command 2>&1`;
    };
    	
    my $numFiles = 0;
    my $openedFiles = '';
     
    foreach(split(/\n/, $out) ) {
        $_ =~ m/(A|M|R) (.*)/;
        my $type = $1;
        my $file = $2;
        my $source = "";
				
        if (defined $file && defined $type) {       
            if (-d $file) {
                    $source = File::Spec->catdir($opts->{scm_workdir}, $file);
            } else {
                    $source = File::Spec->catfile($opts->{scm_workdir}, $file);
            }
                           
            #$self->cpf_debug("source: $source dest: $file file: $source type: $type \n");	
            
            if ($type ne '' && $source ne ''){
                if ($type eq 'A' || $type eq 'M' ) {
                
                   $openedFiles .= $file;
                   $numFiles += 1;
                   
                   if (-f $file) {
                            $self->cpf_addDelta($opts,$source, $file);
                   } elsif (-d $file) {               
                        $self->cpf_addDirectory($file);                        
                   } else {
                        $self->cpf_error("Checked out element \"$file\" does not exist");
                   }             
                } elsif ($type eq 'R'){
                    $openedFiles .= $file;
                    $self->cpf_addDelete($file);

                    $numFiles += 1; 
                }
            }
        }
    }
    $opts->{rt_openedFiles} = $openedFiles;
    
    chdir $here;

    # If there aren't any modifications, warn the user, and turn off auto-
    # commit if it was turned on.

    if ($numFiles == 0) {
        my $warning = 'No files are currently open';
        if ($opts->{scm_autoCommit}) {
            $warning .= '.  Auto-commit has been turned off for this build';
            $opts->{scm_autoCommit} = 0;
        }
        $self->cpf_error($warning);
    } else {
        $self->cpf_closeManifestFiles($opts);
        $self->cpf_uploadFiles($opts);
    }
}

################################################################################
# autoCommit
#
#       Automatically commit changes in the user's client.  Error out if:
#       - A check-in has occurred since the preflight was started, and the
#         policy is set to die on any check-in.
#       - A check-in has occurred and opened files are out of sync with the
#         head of the branch.
#       - A check-in has occurred and non-opened files are out of sync with
#         the head of the branch, and the policy is set to die on any changes
#         within the client workspace.
################################################################################
sub cpf_autoCommit()
{
    my ($self, $opts) = @_;
    
    # Make sure none of the files have been touched since the build started.
    $self->cpf_checkTimestamps($opts);
        
    # Load userName and password from the credential   
    ($opts->{cvsUserName}, $opts->{cvsPassword}) = 
        $self->retrieveUserCredential($opts->{credential}, 
        $opts->{cvsUserName}, $opts->{cvsPassword});
   
    my $here = getcwd();
            
    if (defined ($opts->{dest}) && ("$opts->{dest}" ne "." && "$opts->{dest}" ne "" )) {
        $opts->{dest} = File::Spec->rel2abs($opts->{dest});
        print "Changing to directory $opts->{dest}\n";
        mkpath($opts->{dest});
        if (!chdir $opts->{dest}) {
            print "could not change to directory $opts->{dest}\n";
            exit 1;
        }
    }
    
    # Find the latest revision number and compare it to the previously stored
    # revision number.  If they are the same, then proceed.  Otherwise, do some
    # more advanced checks for conflicts.
   
    my $out = "";
    my $command = "cvs -d $opts->{scm_cvsroot} log";

    eval {
        $out = `$command 2>&1`;
    };
    
    my @lines = split(/=+/, $out);
    my $lastChangeDate = 0;
    my $lastCommitId = 0;
    my $currentDate;
    my $currentCommitId;
    my $date;
    
    foreach my $line (@lines) 
    {
       if (defined $line) {
            $line =~ /date: ([\d\-\/\ \:\w]+)/;
            $date = $1;
            $currentDate = CVSstr2time($date);
            $line =~ /commitid: ([\d\w]+)/;
            $currentCommitId = $1;
            if ( (defined $currentDate) && (defined $lastChangeDate) ) {         
                if($currentDate > $lastChangeDate) {
                    $lastChangeDate = $currentDate;
                    $lastCommitId = $currentCommitId;
                }
            }
        }
    }
    
    $self->cpf_debug("Latest revision: $lastCommitId");

    # If the changelists are different, then check the policies.  If it is
    # set to always die on new check-ins, then error out.

    if ($lastCommitId ne $opts->{scm_lastchange}) {
        $self->cpf_error('A check-in has been made since ecpreflight was started. '
                . 'Sync and resolve conflicts, then retry the preflight '
                . 'build');
    }

    # If there are any updates that overlap with the opened files, then
    # always error out.
    $out = "";
    $command = "cvs -d $opts->{scm_cvsroot} -qn update";   
    eval {
        $out = `$command 2>&1`;
    };
    
    my $numFiles = 0;
    my $openedFiles = '';
     
    foreach(split(/\n/, $out) ) {
        $_ =~ m/(A|M|R) (.*)/;
        my $type = $1;
        my $file = $2;
       
        
        if ($type ne ''){
            if ($type eq 'A' || $type eq 'M' ||  $type eq 'R'  ) {            
               $openedFiles .= $file;               
            }
        }
    }
        
    # If any file have been added or removed, error out.

    if ($openedFiles ne $opts->{rt_openedFiles}) {
        $self->cpf_error("Files have been added and/or removed from the selected "
                . "changelists since the preflight build was launched");
    }

    # Commit the changes.
    $command = " -d $opts->{scm_cvsroot} commit " . " -m \"" . $opts->{scm_commitComment}."\"";
    
    chdir $here;

    $self->cpf_display("Committing changes");
    $self->cpf_cvs($opts, $command, {LogCommand=>1, LogResult=>1});
    $self->cpf_display("Changes have been successfully submitted");
}

###############################################################################
# cpf_driver
# 
# Main program for the application.
#
# Args:
# Return: 
#    changeNumber - a string representing the last change sequence #
#    changeTime   - a time stamp representing the time of last change     
###############################################################################
sub cpf_driver
{
    my ($self,$opts) = @_;
    $self->cpf_display("Executing CVS actions for ecpreflight");

    $::gHelpMessage .= "
CVS Options:
  --cvsroot <path>      The path to the repository.
  --module  <module>    The module name for the preflight.
  --workdir   <path>      The developer's source directory. 
";

    my %ScmOptions = ( 
        "cvsroot=s"             => \$opts->{scm_cvsroot},
        "module=s"              => \$opts->{scm_module},
        "workdir=s"             => \$opts->{scm_workdir},       
    );

    Getopt::Long::Configure("default");
    if (!GetOptions(%ScmOptions)) {
        error($::gHelpMessage);
    }    

    if ($::gHelp eq "1") {
        $self->cpf_display($::gHelpMessage);
        return;
    }    

    $self->extractOption($opts,"scm_cvsroot", { required => 1, cltOption => "cvsroot" });
    $self->extractOption($opts,"scm_module", { required => 1, cltOption => "module" });
    $self->extractOption($opts,"scm_workdir", { required => 1, cltOption => "workdir" });    
    
    my $here = getcwd();
	            
	if (defined ($opts->{scm_workdir}) && ("$opts->{scm_workdir}" ne "." && "$opts->{scm_workdir}" ne "" )) {
		$opts->{scm_workdir} = File::Spec->rel2abs($opts->{scm_workdir});
		print "Changing to directory $opts->{scm_workdir}\n";
		mkpath($opts->{scm_workdir});
		if (!chdir $opts->{scm_workdir}) {
			print "could not change to directory $opts->{scm_workdir}\n";
			exit 1;
		}
    }
    
    # If the preflight is set to auto-commit, require a commit comment.
    if ($opts->{scm_autoCommit} &&
            (!defined($opts->{scm_commitComment})|| $opts->{scm_commitComment} eq "")) {
        $self->cpf_error("Required element \"scm/commitComment\" is empty or absent in "
                . "the provided options.  May also be passed on the command "
                . "line using --commitComment");
    }

     
    my $out = "";
    my $command = "cvs -d $opts->{scm_cvsroot} log";

    eval {
        $out = `$command 2>&1`;
    };         
    
    my @lines = split(/=+/, $out);
    my $lastChangeDate = 0;
    my $lastCommitId = 0;
    my $currentDate = 0;
    my $currentCommitId = 0;
    my $date = 0;
    
    foreach my $line (@lines) 
    {
        if (defined $line) {
			if($line =~ /date: ([\d\-\/\ \:\w]+)/) {
				$date = $1;
				$currentDate = CVSstr2time($date);
				$line =~ /commitid: ([\d\w]+)/;
				$currentCommitId = $1;

				if($currentDate > $lastChangeDate) {
					$lastChangeDate = $currentDate;
					$lastCommitId = $currentCommitId;
				}
			}
		}
    }
    $opts->{scm_lastchange} = $lastCommitId;
    
    $self->cpf_debug("Extracted path: ".$opts->{scm_cvsroot});
    $self->cpf_debug("Latest revision: ".$opts->{scm_lastchange});
    $self->cpf_debug("Module: ".$opts->{scm_module});
    $self->cpf_debug("Workdir: ".$opts->{scm_workdir});    

	chdir $here;
	
    # Copy the deltas to a specific location.

    $self->cpf_copyDeltas($opts);

    # Auto commit if the user has chosen to do so.

    if ($opts->{scm_autoCommit}) {
        if (!$opts->{opt_Testing}) {
            $self->cpf_waitForJob($opts);
        }
        $self->cpf_autoCommit($opts);
    }
}

#-------------------------------------------------------------------------
# helper routines
#-------------------------------------------------------------------------

##########################################################################
#  CVStime2str
#
#  Convert time in seconds since epoch to an CVS formatted
#  time/date string (e.g. "Nov 6, 2008 12:42:36 PM")
#
#   Params:
#       timestamp   -   a GMT timestamp
#
#   Returns:
#       A string containing the time/date in CVS form.
#
##########################################################################
sub CVStime2str($)
{
    my $self = shift;
    my $timestamp = shift;

    # Convert the GMT time stamp to a local time string
    #  (local time seems to be the preferred format for CVS)
    my @months = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul",
                  "Aug", "Sep", "Oct", "Nov", "Dec" );
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
                                                localtime($timestamp);

    # Handle AM/PM and convert to 12-hour time
    my $ampm = ($hour > 11)  ?  "PM" :"AM";
    $hour = 12 if ($hour == 0);
    $hour = $hour - 12 if ($hour > 12);

    # Assemble and return the output format: "Nov 6, 2008 12:42:36 PM"
    my $timeStr =  sprintf("%s %d, %d %02d:%02d:%02d %s",
                                $months[$mon], $mday, $year+1900, 
                                $hour, $min, $sec, $ampm);
    return $timeStr;
}

##########################################################################
#  CVSstr2time
#
#  Convert a date/time string in CVS format to standard
#  time representation.
#
#   Params:
#       timeStr - a string containing the time/date in CVS form
#
#   Returns:
#       t - integer number of seconds since epoch
#
##########################################################################
sub CVSstr2time($)
{
    #my $self = shift;
    my $timeStr = shift;
    
    if (defined $timeStr) {
    # Match on the parts we need: "2010-09-20 21:25:57"
    $timeStr =~ m/(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+) $/i;
	
    # Convert to number of seconds since "epoch"
    my $t = str2time($timeStr);	    
        return $t;
    } else {
      return -1;
    }
}
1;
