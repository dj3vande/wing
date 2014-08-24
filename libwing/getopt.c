/*
WING getopt.
See getopt.txt for a detailed description.
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "getopt.h"

#ifdef _WIN32	/*Win32 defaults: DOS-ish*/
#define DEFAULT_OPTCHARS	"/-"
#define DEFAULT_OPTSEPCHARS	"/"
#define DEFAULT_OPTARGSEP	": "
#define DEFAULT_OPTEND		"--"
#else		/*unixy defaults: Aim for behavior specified by SUS*/
#define DEFAULT_OPTCHARS	"-"
#define DEFAULT_OPTSEPCHARS	""
#define DEFAULT_OPTARGSEP	" "
#define DEFAULT_OPTEND		"--"
#endif

/*Variables in SUSv3 getopt public interface*/
char *optarg;
int optind=1;
int opterr=1;
int optopt;

/*Variables in wing getopt extended public interface*/
const char *wing_optchars;
const char *wing_optsepchars;
const char *wing_optargsep;
const char *wing_optend;

/*Private working data.
  If we leave this nonzero when we return, we're in the middle of a
    multi-option command line argument.
*/
static int arg_idx;

/*Entry points in wing getopt extended public interface*/
void wing_optreset(void)
{
	optarg=NULL;
	optopt=0;
	optind=1;
	arg_idx=0;
}
void wing_optfullreset(void)
{
	wing_optchars=wing_optsepchars=wing_optargsep=wing_optend=NULL;
	opterr=1;
	wing_optreset();
}

static const char *get_optchars(void)
{
	char *env_val;

	if(wing_optchars != NULL)
		return wing_optchars;
	else if((env_val=getenv("WING_OPTCHARS"))!=NULL)
		return env_val;
	else
		return DEFAULT_OPTCHARS;
}

static const char *get_optsepchars(void)
{
	char *env_val;

	if(wing_optsepchars != NULL)
		return wing_optsepchars;
	else if((env_val=getenv("WING_OPTSEPCHARS"))!=NULL)
		return env_val;
	else
		return DEFAULT_OPTSEPCHARS;
}

static const char *get_optend(void)
{
	char *env_val;

	if(wing_optend != NULL)
		return wing_optend;
	else if((env_val=getenv("WING_OPTEND"))!=NULL)
		return env_val;
	else
		return DEFAULT_OPTEND;
}

static const char *get_optargsep(void)
{
	char *env_val;

	if(wing_optargsep != NULL)
		return wing_optargsep;
	else if((env_val=getenv("WING_OPTARGSEP"))!=NULL)
		return env_val;
	else
		return DEFAULT_OPTARGSEP;
}

int getopt(int argc,char * const argv[],const char *optstring)
{
	char *os_ptr;	/*points at current option character in optstring*/
	int this_opt;

	/*This check should never trip if client code is behaving
	    correctly and sensibly, but SUSv3 requires it, and it's
	    a useful paranoia check anyways.
	*/
	if(argv[optind] == NULL)
		return -1;

	/*Are we done processing arguments?*/
	if(arg_idx == 0)
	{
		const char *t;

		if(optind >= argc)	/*no command-line args left*/
			return -1;
		if(argv[optind][0] == '\0')	/*empty string, strchr would match*/
			return -1;
		if(strchr(get_optchars(),argv[optind][0]) == NULL)	/*not option*/
			return -1;
		if(argv[optind][1]=='\0')	/*'-' is not an option*/
			return -1;

		t=get_optend();
		if(*t!='\0' && strcmp(t,argv[optind])==0)
		{
			/*End-of-options marker*/
			optind++;
			return -1;
		}
	}

	if(arg_idx==0)
	{
		/*We've already checked that we're looking at an option
		    and not some other command-line arg.
		  So bump arg_idx to establish an invariant of
		    "argv[optind][arg_idx] is the next option character".
		*/
		arg_idx++;
	}
	else
	{
		/*DOS-style command line handling allows options to be
		    specified as '/a/b/c/d' (where *nix would expect
		    '-abcd' or '-a -b -c -d').
		  If we have options in that form, we'll see a '/' when
		    we get here (we've already checked that we're inside
		    a command-line argument containing options).  We
		    want to step past AT MOST ONE option character.  (We
		    allow the ones we can step past inside a command-line
		    argument to be specified separately from ones that can 
		    introduce options; there's no compatibility-based reason
		    to allow '-a-b'.  If there is enough user demand for
		    using the same list of characters for both introducing
		    and internally separating options, it would be easy to
		    remove optsepchars and use optchars here as well.)
		*/
		/*Note that we DO NOT allow more options to follow an
		    option that accepts an argument, in the same command-line
		    arg.  This would also not be terribly difficult to
		    implement, but it makes the interface harder to specify
		    unambiguously, and requires modifying the argv strings.
		  So we'll save that until we see whether there's massive
		    user demand for it.
		  If we do implement that, we almost certainly do not want
		    to assimilate optsepchars into optchars, since '-' is
		    likely to be a common thing to want in option arguments.
		*/
		if(strchr(get_optsepchars(),argv[optind][arg_idx]) != NULL)
			arg_idx++;
	}

	/*OK, now we know where we expect to find an option.  So it's
	    time to actually extract and check that option.
	*/
	this_opt=(int)argv[optind][arg_idx];
	arg_idx++;
	os_ptr=strchr(optstring,this_opt);
	if(os_ptr == NULL)	/*unknown option*/
	{
		if(argv[optind][arg_idx]=='\0')
		{
			/*We can't do this outside the unknown option check,
			    since we're using arg_idx to see what comes
			    after the option character if we expect an
			    argument.  But both SUSv3 and our assumptions
			    on entry require optind to be incremented before
			    we return a few lines down.
			*/
			arg_idx=0;
			optind++;
		}
		optopt=this_opt;
		if(opterr && optstring[0]!=':')
			fprintf(stderr,"%s: unknown option '%c'\n",argv[0],optopt);
		return '?';
	}

	/*If we get here, we have a valid option and arg_idx indexes
	    the current command-line argument just AFTER the option
	    character.
	*/

	/*Now see if we need an argument*/
	if(os_ptr[1]==':')
	{
		if(argv[optind][arg_idx]=='\0')
		{
			/*No option arg in this command-line arg, get the
			    next one.
			*/
			optind++;	/*step past arg with option name*/
			arg_idx=0;
			if(optind==argc	|| strchr(get_optargsep(),' ')==NULL)
			{
				/*Out of command-line arguments, and nothing
				    for the option arg; or configured to not
				    allow next-command-line-arg for the option
				    argument.
				*/
				optopt=this_opt;
				if(opterr && optstring[0]!=':')
				{
					fprintf(stderr,"%s: Missing argument for option '%c'\n",argv[0],optopt);
				}
				/*Array indexing magic (I tried writing this
				    using the ?: operator, but that was even
				    worse).
				*/
				return (int)"?:"[optstring[0]==':'];
			}
			optarg=argv[optind++];
		}
		else
		{
			/*Option argument in this command-line argument*/
			optarg=argv[optind]+arg_idx;
			if(strchr(get_optargsep(),*optarg) != NULL)
			{
				/*Option separator.  Step over it.*/
				optarg++;
			}
			optind++;
			arg_idx=0;
		}
	}
	else
	{
		/*Don't need an option argument.
		  Check to see if we're at the end of a command-line arg
		    (if we are, we need to update position counters).
		*/
		if(argv[optind][arg_idx]=='\0')
		{
			optind++;
			arg_idx=0;
		}
	}

	/*OK, done everything we need to do, checked everything we need
	    to check, if we get here we have an option to return.
	*/
	return this_opt;
}
