#include "libwing.h"

int wing_glob_foreach(const char *pattern, int (*func)(const char *name, void *env), void *env)
{
	/*The shell does glob expansion on *nix systems, so we don't have to.
	  So just pass along the names we get to the handler function.
	*/
	func(pattern, env);
	return 1;
}
