#ifndef H_LIBWING_GETOPT
#define H_LIBWING_GETOPT

/*Getopt implementation that can handle Windows(DOS)-style options*/
/*See getopt.txt for an in-depth discussion.*/

#ifdef __cplusplus
extern "C" {
#endif

/*Configuration.
  If set to something other than NULL by the application, these override
    both the defaults and the values from the environment for the
    corresponding configuration string.
*/
extern const char *wing_optchars;	/*WING_OPTCHARS*/
extern const char *wing_optsepchars;	/*WING_OPTSEPCHARS*/
extern const char *wing_optargsep;	/*WING_OPTARGSEP*/
extern const char *wing_optend;	/*WING_OPTEND*/

/*The SUS getopt interface*/
extern char *optarg;
extern int optind,optopt;
extern int opterr;

int getopt(int argc, char * const argv[], const char *optstring);


/*Extras that may be useful*/

/*wing_optreset resets anything that may be modified by getopt, but
    does not touch anything that getopt treats as read-only (opterr
    or wing_foo environment overrides).  wing_optfullreset resets
    EVERYTHING to the program start state.
*/
void wing_optreset(void);
void wing_optfullreset(void);

#ifdef __cplusplus
}	/*close extern "C"*/
#endif

#endif
