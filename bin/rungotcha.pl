#!/usr/bin/perl -w

use GOtcha;
use Archive::Tar;
use GOresult;
use FileHandle;
use Cwd;
use BlastHit;
use GOdb;
use Getopt::Long;
use GD;
require "parseblastlib.pl";
# use the GOdb module to talk to the flatfile database
#
# Take in sequence and run a search..

#command line options
my @filelist=();
my @searchdb=(); #blast databases to search
my @excludetaxa=(); #taxa to exclude
my @excludecode=(); #evidence codes to exclude
my @includecode=(); #evidence codes to include (conflicts with excludecode)
my @xref=(); #databases to provide crossreferences for.
my $blastdb=""; # value for BLASTDB
if (exists($ENV{GOTCHA_LIB}) && -e "$ENV{GOTCHA_LIB}/db") {
    $blastdb="$ENV{GOTCHA_LIB}/db";
}
my $blastmat=$ENV{BLASTMAT}; # value for BLASTMAT
my $infile=""; #sequence input file
my $seqdb="unassigned";
my $outfile="gotcha.$$"; # result output file
my $seqtype="A"; #sequence type T or P Protein, F or D or N DNA, A Autodetect
my $goidx="";# go term index
my $html="";  # create an html page index.html.
my $webpath=""; # path to web server with GOtcha data
my $linkidx=""; #go link index.
my $scoreidx=""; # Empirical score estimates index
my $linkprefix=""; # prefix to prepend to all relative links
my $tmpdir="/tmp"; # temporary directory for sequence processing
my $fastdir="";  # high speed file system directory on which to build gotcha results
my $mindp = 40; # minimum data points to use for determining probabilities.
my $incomp=0; # compressed tar archive for existing results
my $outcomp=0; # compress tar archive for external results
my $reprocess=""; # reprocess results using this tag
my $tarfile=""; # read/write this tar file for results
my $nopng=0; # don't generate graphics. Text only output
my $cutoff=0; # score cutoff for graphics and results reporting
my $topblast=""; # generate a list of GO terms corresponding to the top blast hits
my $embosspath=`which seqret`;
chomp $embosspath;
$embosspath=~s!/seqret!!;
    my $dotprog=`which dot`;
    chomp $dotprog;
my $blastpath=`which blastall`;
$blastpath=~s!/blastall!!;
chomp $blastpath;
my $debug=1;
my $contigid=0;
my $config=""; # configuration file to allow options to be set.
my $dotfontname="Arial";
my $dotfontpath="/usr/share/fonts/truetype";
GetOptions('searchdb=s' =>\@searchdb,
	   'excludetaxa=i' =>\@excludetaxa,
	   'excludecode=s'=>\@excludecode,
	   'includecode=s'=>\@includecode,
	   'infile=s'=>\$infile,
	   'webpath=s'=>\$webpath,
	   'blastdb=s'=>\$blastdb,
	   'blastmat=s'=>\$blastmat,
	   'seqtype=s'=>\$seqtype,
	   'outfile=s'=>\$outfile,
	   'html=s'=>\$html,
	   'seqdb=s'=>\$seqdb,
	   'contigid=i'=>\$contigid,
	   'goidx=s'=>\$goidx,
	   'tar=s'=>\$tarfile,
	   'mindatapoints=i'=>\$mindp,
	   'incomp'=>\$incomp,
	   'fastdir=s'=>\$fastdir,
	'embosspath=s'=>\$embosspath,
	'blastpath=s'=>\$blastpath,
	   'dotprog=s'=>\$dotprog,
	   'outcomp'=>\$outcomp,
	   'linkidx=s'=>\$linkidx,
	   'scoreidx=s'=>\$scoreidx,
	   'linkprefix=s'=>\$linkprefix,
	   'dotfontpath=s'=>\$dotfontpath,
	   'dotfontname=s'=>\$dotfontname,
	   'reprocess=s'=>\$reprocess,
	   'cutoff=i'=>\$cutoff,
	   'debug=i'=>\$debug,
	   'xref=s'=>\@xref,
	   'config=s'=>\$config,
	   'topblast'=>\$topblast,
	   'nopng'=>\$nopng,
	   'tmpdir=s'=>\$tmpdir
	   );

unless ($config || ! exists($ENV{GOTCHA_LIB})) {
    $config="$ENV{GOTCHA_LIB}/data/gotcha.conf";
}
if ($config) {
    my @filedb=();
    # read in the config file and populate command line parameters where not set.
    if (-e $config) {
	open (CONF, $config) or (warn "Cannot open configuration file $config:$!\n" and next);
	while ($line=<CONF>){
debug("CONFIG: $line",2);
	    chomp $line;
	    $line=~s/ *#.*$//; #remove comments
	    $line =~s/^ *//; # remove padding spaces.
	    $line =~s/ *$//; # remove trailing spaces.
	    next if $line=~/^ *$/; #remove blank lines.
	    ($key, $value)= split / +/, $line, 2;
debug("key: $key, value: $value",2);

	  foreach ($key)  {
#	      print STDERR 
debug("evaluating $key",2);
	      /searchdb/ and do {  unless (@searchdb) { push @filedb, $value; last ;}};
	      /excludetaxa/ and do {unless (@excludetaxa) { push @excludetaxa, $value; last ;}};
	      /excludecode/ and do {unless (@excludecode) { push @excludecode,  $value; last ;}};
	      /includecode/ and do {unless (@includecode) { push @includecode,  $value; last ;}};
	      /infile/ and do {unless ($infile) { $infile = $value; last ;}};
	      /webpath/ and do {unless ($webpath) { $webpath = $value; last ;}};
	      /blastdb/ and do {unless ($blastdb) { $blastdb = $value; last ;}};
	      /blastmat/ and do {unless ($blastmat) { $blastmat = $value; last ;}};
	      /seqtype/ and do {unless ($seqtype) { $seqtype = $value; last ;}};
	      /outfile/ and do {unless ($outfile ne "gotcha.$$") { $outfile = $value; last ;}};
	      /html/ and do {unless ($html) { $html = $value; last ;}};
	      /contigid/ and do {unless ($contigid) { $contigid = $value; last ;}};
	      /goidx/ and do {unless ($goidx) { $goidx = $value; last ;}};
	      /tar/ and do {unless ($tar) { $tar = $value; last ;}};
	      /mindatapoints/ and do {unless ($mindp != 40) { $mindp = $value; last ;}};
	      /incomp/ and do {unless ($incomp) { $incomp = $value; last ;}};
	      /fastdir/ and do {unless ($fastdir) { $fastdir = $value; last ;}};
	      /outcomp/ and do {unless ($outcomp) { $outcomp = $value; last ;}};
	      /linkidx/ and do {unless ($linkidx) { $linkidx = $value; last ;}};
	      /scoreidx/ and do {unless ($scoreidx) { $scoreidx = $value; last ;}};
	      /linkprefix/ and do {unless ($linkprefix) { $linkprefix = $value; last ;}};
	      /dotfontpath/ and do {unless ($dotfontpath ne "/usr/share/fonts/truetype") { $dotfontpath = $value; last ;}};
	      /dotfontname/ and do {unless ($dotfontname ne "Arial") { $dotfontname = $value; last ;}};
	      /dotprog/ and do {unless ($dotprog) { $dotprog = $value; last ;}};
	      /reprocess/ and do {unless ($reprocess) { $reprocess = $value; last ;}};
	      /cutoff/ and do {unless ($cutoff) { $cutoff = $value; last ;}};
	      /debug/ and do { $debug = $value; last ;};
	      /xref/ and do {unless (@xref) { push @xref, $value; last ;}};
	      /topblast/ and do {unless ($topblast) { $topblast = $value; last ;}};
	      /blastpath/ and do {unless ($blastpath) {$blastpath= $value; last;}};
	      /embosspath/ and do {unless ($embosspath) {$embosspath= $value; last;}};
	      /nopng/ and do {unless ($nopng) { $nopng = $value; last ;}};
	      /tmpdir/ and do {unless ($tmpdir ne "/tmp") { $tmpdir = $value; last ;}};

	  }
	}
    } else {
	warn "Config file $config could not be found: $!\n";
    }
#    print STDERR "FILE: ",join(",", @filedb),"\n";
#    print STDERR "SEARCH: ", join(",", @searchdb),"\n";
    if (@filedb) { @searchdb=@filedb;}
#    print STDERR "SEARCH: ",join(",", @searchdb),"\n";
}

@searchdb=split /,/, (join ',', @searchdb);
@excludecode=split /,/, uc (join ',', @excludecode);
@xref=split /,/, uc (join ',', @xref);
@includecode=split /,/, uc (join ',', @includecode);
my $noiea=0;



debug("searching ". (scalar @searchdb). " databases",1);
if ($linkprefix eq "") { $linkprefix=$outfile;}

if (scalar @includecode && scalar @excludecode) {
    print STDERR "specify either --excludecode or --includecode but not both.\n";
    exit; 
}
if (scalar @excludecode ) {
    foreach my $c (@excludecode){
	if ($c eq 'IEA'){
	    $noiea=1;
	}
    }
}elsif (scalar @includecode){
    $noiea=1;
    foreach my $c (@includecode){
	if ($c eq "IEA"){
	    $noiea=0;
	}
    }
}
	

debug("go index: $goidx",2);
debug("link index: $linkidx",2);
debug("score index: $scoreidx",2);

if ($ENV{GOTCHA_LIB}) {
    if (! $goidx && -e "$ENV{GOTCHA_LIB}/data/terms.idx") {
	$goidx="$ENV{GOTCHA_LIB}/data/terms.idx";
    }
    if (! $linkidx && -e "$ENV{GOTCHA_LIB}/data/links.idx") {
	$linkidx="$ENV{GOTCHA_LIB}/data/links.idx";
    }
    if (! $scoreidx && -e "$ENV{GOTCHA_LIB}/data/scores.idx") {
	$scoreidx="$ENV{GOTCHA_LIB}/data/scores.idx";
    }
}

debug("go index: $goidx",2);
debug("link index: $linkidx",2);
debug("score index: $scoreidx",2);
if (! (scalar @searchdb && $goidx && $linkidx && $blastpath && $embosspath && -e "$blastpath/blastall" && -e "$embosspath/seqret") ){

    unless (scalar @searchdb) {
	print STDERR "No search databases set\n";
    }
    unless ($goidx) {
	print STDERR "No GO terms DB defined\n";
    }
    unless ($linkidx) {
	print STDERR "No GO links DB defined\n";
    }
    unless (-e "$blastpath/blastall") {
	print STDERR "cannot find blastall in $blastpath/blastall\n";
    }
    unless (-e "$embosspath/seqret") {
	print STDERR "cannot find seqret in $embosspath/seqret\n";
    }

    print STDERR <<Usage;
GOtcha usage:    rungotcha.pl [options]
	--infile <filename>      (optional) Sequence file defaults to STDIN
	--outfile <directory>    (optional) Output directory for results. 
                                            Defaults to gotcha.<jobid> 
	--searchdb <dbname>      (required multi) Blast databases to use.
	--blastdb <directory>    (optional) Directory containing BLAST databases
	                                    Defaults to \$BLASTDB or \$GOTCHA_LIB/db if set.
	--blastmat <directory>   (optional) Direcotry containing BLAST matrices
	                                    Defaults to \$BLASTMAT
	--blastpath <directory>  (optional) Directory to NCBI executables. 
	                                    This should be found automatically 
					    if it is in the path
	--embosspath <directory> (optional) Directory to EMBOSS executables. 
	                                    This should be found automatically 
					    if they are in the path
	--seqtype [T|P|F|D|N|A]        (optional) Protein (T or P) or DNA (F or N or D) sequence
	                                    Defaults to Autodetect (A)
	--excludetaxa <taxon>    (optional multi) taxa to exclude (NCBI 
                                                  taxonomic id)
        --includecode <code>     (optional multi) Only use links with these 
	                         evidence codes. 
                                 Cannot be used with --excludecode
        --excludecode <code>     (optional multi) Only use links without 
	                                          these evidence codes. 
                                       Cannot be used with --includecode
        --linkprefix <path>      (optional) prefix to relative WWW links - 
	                                    Default gotcha.<jobid>
	--goidx <filename>       (required) Filename for the go database index file.
	--linkidx <filename>     (required) Filename for the Go database links index file.
	--scoreidx <filename>     (optional) Filename for the Go database scores index file.
	--tmpdir <directorypath> (optional) Path to store temporary files. default /tmp
	--contigid <integer>     (optional) Numerical id for the sequence for insertion 
                                            in SQL output. Default 0.
        --dotfontpath <directorypath>	(optional) path to truetype fonts for dot.
	                                    Default /usr/share/fonts/truetype
        --dotfontname <name>	 (optional) Name of truetype font for dot.
	                                    Default Arial
	--reprocess <name>       (optional) Do not rerun searches, just reprocess the results.
	--mindatapoints <integer> (optional) minimum number of datapoints to use when assigning probabilities (default 40)
	--nopng                  (optional) Do not produce graphics. (saves space for high throughput analysis)
	--tar  <filename>        (optional) Produce results as a tar archive, not as single files.
	--incomp                 (optional) existing tar file of results is compressed.
	--outcomp                (optional) Compress tar file upon creation
	--fastdir <dirname>      (optional) location to build results
	--xref <dbname>          (optional) provide a list of database cross references for dbname in gotcha.dbname
	--topblast               (optional) Provide a list of GO terms derived from the top annotated hit of each database as topblast.hits[.reprocess]
	--cutoff <integer>       (optional) Restrict HTML output to terms with a probability higher than n\% 
	                                    Default 0. 
	--debug <integer>        (optional) Print debugging output to STDERR
	                          0=minimal, 1=standard 2-4 increasing verbosity. Default 1.

multi options can be specified more than once.
Usage
    exit;
}

#### BLAST setup

if ($blastdb) {
    $ENV{'BLASTDB'}=$blastdb;
}
if ($blastmat) {
    $ENV{'BLASTMAT'}=$blastmat;
}
unless ($ENV{'BLASTDB'}) {
    die "BLASTDB is not set. GOtcha cannot run.\n";
}
$blastdb=$ENV{'BLASTDB'};

my %seqtypes=(T=>'P',
		P=>'P',
		F=>'N',
		N=>'N',
		D=>'N');


%blastprog=( 
	     #sequence=>database
	     N=>{
		 n=>'blastn',
		 p=>'blastx'
		 },
	     P=>{
		 n=>'tblastn',
		 p=>'blastp'
		 }
	     );

#### EMBOSS setup

#### Temporary file name

    $tmpname=time().".".$$;

#create the output directory

if ($tarfile && $fastdir && -e $fastdir && -d $fastdir ) {
    $fastdir .= "/";
} else {
    $fastdir="";
}

if (-e $fastdir.$outfile && ! $reprocess) {
    die "output directory already exists - exiting\n";
}elsif ( $reprocess ) {
    if ($tarfile && -e $tarfile) {
	my $tar = Archive::Tar->new($tarfile,$incomp);
	if ($tar) {
	    $tar->extract();
	    foreach my $f ($tar->list_files()) {
		if ($f =~/^$outfile/) {
		    $f=~ s!^$outfile/!!;
		    push @filelist, $f;
		}
	    }
	}
    }
    unless (-e $fastdir.$outfile ) {
	warn "No existing results in $outfile. Running searches.";
	$reprocess="";
	system ("mkdir -p $fastdir$outfile");
	if (! -e $fastdir.$outfile ) {
	    die "could not create directory for output\n";
	}
    }
}else {
    unless ($reprocess){
	system ("mkdir -p $fastdir$outfile");
	if (! -e $fastdir.$outfile ) {
	    die "could not create directory for output\n";
	}
    }
}


@confdesc=("very poor", "poor", "low", "fair", "fairly good", "good", "high", "very high", "excellent");

#read in the sequence.
my %databases=();

debug("seqtype originally $seqtype",2);
unless ($reprocess) {
    $tmpseqin = $tmpdir."/".$tmpname.".inseq";
    open INSEQ,">$tmpseqin";
    if ($infile && -e $infile && -r $infile) {
	open INFILE, $infile;
	while (<INFILE>) {
	    print INSEQ;
	}
	close INFILE;
    } else {
	debug("reading sequence from STDIN",1);
	while (<>){
	    print INSEQ;
	}
    }
    close INSEQ;
    if ($seqtype eq "A" || ! exists($seqtypes{uc $seqtype})){
	my @seqinfo;
	if (open INFO , "$embosspath/infoseq $tmpseqin -stdout -auto |") {
	    @seqinfo=<INFO>;
	    close INFO;
	}else {
	    print "could not obtain sequence info from ",($infile?$infile:"STDIN")."\n";
	    exit;
	}
	
	foreach $l (@seqinfo) {
	    @bits=split " ",$l;
	    unless ($seqtype ne 'A') {
		if ($bits[3] eq 'N' ||$bits[3] eq 'P'){
		    $seqtype=$bits[3];
		}
	    }
	}
    } else {
	if (exists($seqtypes{uc $seqtype})){
	    $seqtype=$seqtypes{uc $seqtype};
	}
    }
#print STDERR "seqtype is $seqtype\n";

#convert to fasta
    system( "$embosspath/seqret $tmpseqin $fastdir$outfile/query.seq -osf fasta -auto");
    push @filelist, "query.seq";

# run blast searches and process them


# build an index of available blast databases
}    
debug("blastdb $blastdb",2);
    opendir BLASTDB, $blastdb;
    while ($file=readdir BLASTDB) {
	if ($file=~/^(.+)\.([pn])in$/) {
	    $databases{lc $1}=$2;
	    debug( "found  $1 type $2",2);
	}
    }
    closedir BLASTDB;
    
    

my $godb;
#get a handle to the GO database
debug("GO $goidx SEQ $linkidx SCORE $scoreidx",2);
if ($scoreidx){
    $godb = new GOdb($goidx,$linkidx,$scoreidx);
}else{
    $godb = new GOdb($goidx,$linkidx);
}

debug("godb $godb",2);
unless (ref($godb) eq "GOdb") {
	die "cannot create GO database on ".$ENV{"HOSTNAME"}."\n";
}
#create a structure to hold the results
$godb->debug_on($debug);

my $gotcha=GOtcha->new($godb, $noiea);
$gotcha->mindatapoints($mindp);

foreach $b (@searchdb) {

    unless (exists ($databases{lc $b}) ){
	warn "Database $b not found. Skipping ... \n";
	next;
    }
    debug("BLASTMAT ".$ENV{BLASTMAT}." $blastmat BLASTDB ".$ENV{BLASTDB}. " SEQTYPE $seqtype DBTYPE ".$databases{lc $b},2);
    $resfile="$fastdir$outfile/$b.blast";
# create a results object for this database

    push @filelist, "$b.blast";
    my $results=GOresult->new($godb);
    debug("$b: $blastpath/blastall -p $blastprog{$seqtype}{$databases{lc $b}} -d $b -i $outfile/query.seq -o $resfile",2);
    if ($reprocess) {
	unless (-e "$resfile" ){
	    debug("skipping $resfile for $reprocess...",1);
	    next;
	}
    }else{
	debug("$b:$databases{$b}:$blastprog{$seqtype}{$databases{$b}}",2);
	if (system( "export BLASTDB=$blastdb; export BLASTMAT=$blastmat; $blastpath/blastall -p $blastprog{$seqtype}{$databases{lc $b}} -d $b -i $outfile/query.seq -o $resfile")){
	}
    }
    @hitlist =  &parsesearch($resfile);
    foreach $hit (@hitlist) {
# generate a GO term list and add the scores.
	if ($hit->getRscore() >0) {
	    my @golist=();
	    if (scalar @includecode >0) {
		@golist=$godb->getgoforid($hit->gethitname(),1,@includecode);
	    }else{
		@golist=$godb->getgoforid($hit->gethitname(),0,@excludecode);
	    }		
	    foreach $go (@golist){
		$results->goscore($go, $hit->getRscore());
	    }
	    $results->add_hit($hit->gethitname(), $hit->getRscore());
	}
    }
    
    
#if there are hits then add the database to the GOtcha object
    if ($results->maxscore()>0) {
	$gotcha->addgoresult($b,$results);
    }
}

# all searches have been run. Now to output some results.
# write results for each individual search and the combined search to output directory
$suffix="";
if ($reprocess){
    $suffix=".$reprocess";
    # need to unpack tar archive if specified. FIXME
}

if ($topblast){
    my %seqs=$gotcha->tophits();
    my %bg=(); #place holder for GO terms.
    foreach my $s (keys %seqs){
	my @gc=();
	if (scalar @includecode >0) {
	    @gc=$godb->getgoforid($s,1,@includecode);
	}else{
	    @gc=$godb->getgoforid($s,0,@excludecode);
	}		
	foreach my $c (@gc) {
	    $gt=$godb->findgoterm($c);
	    my @gca=$gt->get_ancestorlist();
	    foreach my $a (@gca,$c) {
		unless (exists($bg{$a}) && $bg{$a} > $seqs{$s}){
		    $bg{$a}=$seqs{$s};
		}
	    }
	}
    }
    open TOPBLAST, ">$fastdir$outfile/topblast.hits$suffix" or die "error opening topblast.hits$suffix: $!\n";
    push @filelist, "topblast.hits$suffix";
    print TOPBLAST "#GO terms from the top BLAST hit for each database\n#\n";
    foreach my $r (sort {$bg{$b} <=> $bg{$a}} keys %bg) {
	my $g=$godb->findgoterm($r);
	print TOPBLAST "$r\t$bg{$r}\t".$g->ontology()."\n";
    }
    close TOPBLAST;
}

foreach my $b ($gotcha->listdatabases()){
    open GOTCHA, ">$fastdir$outfile/$b.gotcha$suffix" or die "error opening output file $outfile/$b.gotcha$suffix : $!\n";
    push @filelist, "$b.gotcha$suffix";
    print GOTCHA $gotcha->getgoresult($b)->write();
    close GOTCHA;
}
open GOTCHA, ">$fastdir$outfile/gotcha.res$suffix" or  die "error opening output file $outfile/gotcha.res$suffix : $!\n";
    push @filelist, "gotcha.res$suffix";
print GOTCHA $gotcha->write();
close GOTCHA;
foreach my $x (@xref) {
    open XGOTCHA, ">$fastdir$outfile/gotcha.dbxref.$x$suffix" or  die "error opening output file $outfile/gotcha.dbxref.$x$suffix : $!\n";
    push @filelist, "gotcha.dbxref.$x$suffix";
    print XGOTCHA $gotcha->writexref($x);
    close XGOTCHA;
} 
foreach my $o (qw/C F P/){
    open DOTCHA, ">$fastdir$outfile/gotcha.$o.dot$suffix" or  die "error opening output file $outfile/gotcha.$o.dot$suffix : $!\n";
    push @filelist, "gotcha.$o.dot$suffix";
    print DOTCHA $gotcha->writedot($o, $cutoff);
    close DOTCHA;
}
#write SQL file for input to a database.
open GOTCHA, ">$fastdir$outfile/gotcha.sql$suffix" or  die "error opening output file $outfile/gotcha.sql$suffix : $!\n";
    push @filelist, "gotcha.sql$suffix";
print GOTCHA $gotcha->writesql($contigid,$seqdb,$reprocess);
close GOTCHA;

#write the dot input file for the combined search and generate the appropriate png, image map and javascript for  incorporation into a web page
unless ($nopng){
    
    $gotcha->dotfontpath($dotfontpath);
    $gotcha->dotfontname($dotfontname);
    
    
    my %ontologies=(
		    C=>"Cellular Compartment",
		    F=>"Molecular Function",
		    P=>"Biological Process"
		    );

    my $htmltext="";
    if ($dotprog) {
	$htmltext.="<SCRIPT Language=javascript SRC=$linkprefix/gotcha$suffix.js ></SCRIPT>\n";
	
	$htmltext .=$gotcha->htmlhead();
	$htmltext .=<<HEADLINKS;
	<p><a href=#C>Cellular Compartment</a>&nbsp;-&nbsp;<a href=#F>Molecular Function</a>&nbsp;-&nbsp;<a href=#P>Biological Process</a><p>
	    
HEADLINKS
	    
        open IMGMAP, ">$fastdir$outfile/gotcha.imap$suffix" or die "cannot open Image Map file $outfile/gotcha.imap$suffix :$!\n";
	    push @filelist, "gotcha.imap$suffix";

	my $javascript=<<JSCRIPT;

function displayGOinfo(goid, ont){
    if (GOinfo[goid] != null){
	eval("document.gotchainfoform"+ont+".gotchainfo"+ont+".value=GOinfo[goid]");
    }
}
function getX(obj) { return( obj.offsetParent==null ? obj.offsetLeft : obj.offsetLeft+getX(obj.offsetParent) ); }
function getY(obj) { return( obj.offsetParent==null ? obj.offsetTop : obj.offsetTop+getY(obj.offsetParent) ); }

var GOinfo=new Array()

JSCRIPT
;
	my $postjs="";
	foreach my $o (qw/C F P/){
	    $htmltext.="<h2><a name=$o>$ontologies{$o}<a></h2>\n";
	    
##	print STDERR "count($o)=".$gotcha->count($o)."\n";
	    if ($gotcha->count($o)>0){
		system ("$dotprog -Tpng -o$outfile/gotcha_$o$suffix.png $outfile/gotcha.$o.dot$suffix ");
		system ("$dotprog -Tismap -o$fastdir$outfile/dot.$o$suffix.imap $outfile/gotcha.$o.dot$suffix ");
		my $img=GD::Image->new("$outfile/gotcha_$o$suffix.png");
		open IMG, ">$fastdir$outfile/gotcha_$o$suffix.png" or die "cannot rewrite $outfile/gotcha_$o$suffix.png :$!\n";
		binmode IMG;
		print IMG $img->png();
		close IMG;
    push @filelist, "gotcha_$o$suffix.png";
		my ($imgw,$imgh)=$img->getBounds();
		my $yhr=300/$imgh;
		my $xhr=600/$imgw;
		my $imgratio=$xhr<$yhr?$xhr:$yhr;  
		my $simgh=int($imgratio* $imgh);
		my $simgw=int($imgratio* $imgw);
		my $zr=1;
		if ($imgh > 400 && $imgw >400) {
		    $zr=2;
		}
		my $zimgh=int($imgh/$zr);
		my $zimgw=int($imgw/$zr);
		
#    system("convert -size 600x$simgh $outfile/gotcha.png $outfile/gotcha_web.png");
#    system("convert -scale 50%x50% $outfile/gotcha.png $outfile/gotcha_zoom.png");

		my $simg=GD::Image->new($simgw,$simgh);
		$simg->copyResized($img,0,0,0,0,$simgw,$simgh,$imgw,$imgh);
		open SPNG, ">$fastdir$outfile/gotcha_web_$o$suffix.png" or die "cannot open $outfile/gotcha_web.$o$suffix.png :$!\n";
		binmode SPNG;
		print SPNG $simg->png();
		close SPNG;
    push @filelist, "gotcha_web_$o$suffix.png";
		my $zimg=GD::Image->new($zimgw,$zimgh);
		$zimg->copyResized($img,0,0,0,0,$zimgw,$zimgh,$imgw,$imgh);
		open SPNG, ">$fastdir$outfile/gotcha_zoom_$o$suffix.png" or die "cannot open $outfile/gotcha_zoom.$o$suffix.png :$!\n";
		binmode SPNG;
		print SPNG $zimg->png();
		close SPNG;
    push @filelist, "gotcha_zoom_$o$suffix.png";
		
#now read in the image map file and parse.
	
		open DOTMAP, "$fastdir$outfile/dot.$o$suffix.imap" or die "cannot open dot output $outfile/dot.$o$suffix.imap :$!\n";
	    push @filelist, "dot.$o$suffix.imap";

		$htmltext .= "<MAP name=gotchamap_$o>\n";
		while (<DOTMAP>){
		    chomp;
		    my $area=$_;
		    my @f=split / /, $area;
		    my $coords=join ',',$f[2],$f[1];
		    $coords=~s/[\)\(]//g;
		    my @coords=split /,/,$coords;
		    my @sc=();
		    foreach my $c (@coords){
			push @sc, int($c*$imgratio);
		    }
		    #$sc[1]*=3;
		    #$sc[3]*=3;
		    $coords=join',',@sc;
		    my $goid=$f[4];
		    $goid=~s/^GO:(\d+) *.*$/$1/;
		    my $score=$gotcha->probscore($goid);
		    my $goterm=$godb->findgoterm($goid);
		    my $desc=$goterm->description();
		    my $info="GO:$goid".'\n';
		    if (scalar $goterm->synonyms()){
			$info.='Synonyms:\n'.join('\n',$goterm->synonyms()).'\n';
		    }
		    $info .='Description: '.$goterm->description().'\n';
		    $info .='Definition: '.$goterm->definition();
		    if (scalar $goterm->defrefs()){
			$info .='\nReferences:\n'.join('\n',$goterm->defrefs());
		    }
		    my $alt="GO:$goid $desc; Score: $score";
		    $info=~s/(\')/\\$1/g;
		    $javascript .= "GOinfo[\"GO:$goid\"]='$info'\n";
		    $htmltext .= "<AREA ID=\"GO$goid\" ALT=\"$alt\" COORDS=\"$coords\" onMouseOver=\"displayGOinfo('GO:$goid','$o')\" HREF=#GO:$goid shape=rect>\n";
		$postjs.="document.getElementById(\"GO$goid\").onmousemove = follow$o;\n"
		}
		close DOTMAP;
		$htmltext .= "</MAP>\n";
		
		$javascript .= <<JSCRIPT;    
  function follow$o(e) {
  var g_small =  document.getElementById("gotcha_small_$o");
  var x = e.layerX - getX(g_small);//x coordinate in the small image
  var y = e.layerY - getY(g_small);//y coordinate in the small image
  var img_x = $zimgw;
  var img_y = $zimgh;
  var xbord = Math.floor(100*$simgw/img_x); 
  var ybord = Math.floor(100*$simgh/img_y);

  x = x - xbord;
  y = y - ybord;
  if( x < 1 ) x = 1;
  if( x > ($simgw-2*xbord) ) { x=($simgw-2*xbord); }
  if( y < 1 ) { y = 1; }
  if( y > ($simgh-2*ybord) ) { y=($simgh-2*ybord); }
  var my_x = Math.floor($zimgw*x/$simgw);
  var my_y = Math.floor($zimgh*y/$simgh);
  var posstr = String($zimgw-my_x)+" "+String($zimgh-my_y);
  window.status = posstr;
  document.getElementById("gotcha_zoom_$o").style.backgroundPosition = posstr;
}
JSCRIPT
    ;

		$conftext=substr(" ".$gotcha->confidence($o),1,3);
		if ($gotcha->confidence($o)>9) {
		    $conftext .=" ($confdesc[9])";
		}else{
		    $conftext .=" (".$confdesc[int($gotcha->confidence($o))].")";
		}
		$htmltext .=<<HTMLTEXT;
<table><td>
<FORM name=gotchainfoform$o>
<textarea style="font: 10px verdana,arial;" cols=80 rows=6 name=gotchainfo$o>Move the mouse over the image. If your browser supports DHTML and has javascript enabled then information on each GO term will appear here. Otherwise, scroll down and view the list.</textarea>
</form>
</td><td><div style="background: url('$linkprefix/gotcha_zoom_$o$suffix.png\');
            height: 200px;
            border: 1px #aaaaaa solid; 
            width: 200px;" 
     id="gotcha_zoom_$o">&nbsp;</div></td></tr></table>
<IMG SRC=$linkprefix/gotcha_web_$o$suffix.png USEMAP=#gotchamap_$o id="gotcha_small_$o"><br>
<a href=$linkprefix/gotcha_$o$suffix.png>Full size image ($imgw x $imgh)</a>
HTMLTEXT
;
		$htmltext .=$gotcha->writehtml($o,"\"http://www.godatabase.org/cgi-bin/go.cgi?action=replace_tree&query=","&search_constraint=terms\"",$cutoff );
	    }
	}
	$htmltext .=<<SCRIPTTAIL
<script>
window.captureEvents(Event.MOUSEMOVE);
document.getElementById("gotcha_small_C").onmousemove = followC;
document.getElementById("gotcha_small_F").onmousemove = followF;
document.getElementById("gotcha_small_P").onmousemove = followP;
$postjs
</script>
SCRIPTTAIL
;
    
	$htmltext .= "</div>\n";
	$htmltext .= "</div>\n";
	
	print IMGMAP $htmltext;
	close IMGMAP;

	if ($html) {
	    open HTML, ">$fastdir$outfile/index$suffix.html" or die "cannot create web page $outfile/index$suffix.html:$! \n";
	    push @filelist, "index$suffix.html";
	    print HTML indexpage($html,$htmltext,$webpath);
	    close HTML;
	}
	open IMGJS, ">$fastdir$outfile/gotcha$suffix.js" or die "cannot open JavaScript file $outfile/gotcha$suffix.js :$!\n";
    push @filelist, "gotcha$suffix.js";
	print IMGJS $javascript;
	close IMGJS;
    }
}
open JOB,">$fastdir$outfile/job$suffix.status" or die "could not open job.status file :$!\n";
    push @filelist, "job$suffix.status";
print JOB "Complete\n";
close JOB;

#now write out tar archive if neccessary.FIXME
if ($tarfile) {
    my $tarout = Archive::Tar->new();
    debug( "tarfile $tarout",2);
    debug("cwd is".cwd(),1);
    map {s!^(.*)$!$outfile\/$1!;} @filelist;
    debug("adding files to tar archive: ". join("\n", @filelist),3);
    foreach my $f (@filelist) {
    my @myfiles = $tarout->add_files($f);
    debug("added $myfiles[0] of $f",3);
    	debug("opening $f for archiving",3);
	open FN, "$fastdir/$f" or warn "cannot open file $f archiving: $!\n";
	my $content="";
	while (<FN>) {
	    $content .=$_;
	}
	close FN;
	$tarout->replace_content($f,$content);
	#unlink "$fastdir$f";
    }
    #rmdir $outfile;
    $tarout->write($tarfile, $outcomp);
# need to delete files. Dont do this until tested FIXME.

}
	



sub parsesearch {
    my $filename=shift;
# perform the search and return the array of BlastHits
    my @hitlist=();
    eval '@hitlist=parseblast($filename)';
    return @hitlist;
}


sub debug {
    my $text=shift;
    my $level=shift;
    if ($debug>=$level) {
	print STDERR "DEBUG: $text\n";
    }
}


sub indexpage {
    my $title=shift;
    my $body=shift;
    my $server=shift;
    my $template =<<TEMPLATE;
<html>
  <head>
    <title>
PAGETITLE
</title>
  </head>
  <body>
    <div class=main style="color: #FFFFFF; background-color: #000080; font-family: "Century Schoolbook Times serif;>
      <table>
        <tr><td width=150><img src=WEBURLgotcha-logo.jpg width=150></td><td style="font-size: 28pt; font-weight: bold;color: #FFFFFF; padding: 10pt;text-align:center">

PAGETITLE
        </td></tr>
        <tr><td valign=top>
          <div style="padding: 5pt; font-family: Helvetica, sanserif;font-size:14pt;font-weight: bold;color:#FFFFFF">About GOtcha 
            <div style="padding-left:10pt ; margin-top: 10pt; font-size: 12pt;">
              <a href=WEBURLmethod.html style="color: #FFFFFF; text-decoration: none">Method</a><br>
	      <a href=WEBURLgotcha.php style="color: #FFFFFF; text-decoration: none">Search</a><br>
              <a href=WEBURLhelp.html style="color: #FFFFFF; text-decoration: none">Help</a><br>
              <a href=WEBURLfaq.html style="color: #FFFFFF; text-decoration: none">FAQ</a><br>

              <!-- <a href=WEBURLmethod.html style="color: #FFFFFF; text-decoration: none">References</a><p>-->
            </div>
            <p>Links
            <div style="padding-left:10pt ; margin-top: 10pt; font-size: 12pt;">
              <a href="http://www.compbio.dundee.ac.uk" style="color: #FFFFFF; text-decoration: none">Barton Group</a><br>
              <a href="http://www.geneontology.org" style="color: #FFFFFF; text-decoration: none">Gene Ontology</a><br>
            </div>
          </div>

        </td><td style="background-color: #FFFFFF; font-family:Helvetica sanserif">
          <div class=header style="background-color: #FFFFFF;padding:10pt ">
PAGEBODY
            <div class=footer style="padding:10pt; color: #000080; text-align:center;font-size:10pt">The GOtcha server is developed and maintained by <a href=mailto:d.m.a.martin\@dundee.ac.uk>Dr. David Martin</a> at the <a href=http://www.dundee.ac.uk/biocentre>Wellcome Trust Biocentre, University of Dundee</a>.
          </div>
        </td></tr>
      </table>
    </div>

  </body>
</html>

TEMPLATE

    unless ($server) { $server="";}
    $template=~s/PAGEBODY/$body/;
    $template =~ s/PAGETITLE/$title/g;
    if ($server) {$server .="/";}
    $server=~s!//$!/!;
    $template =~ s!WEBURL!$server!g;
    return $template;
}
