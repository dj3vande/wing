#ifndef H_LIBWING_LIBWING
#define H_LIBWING_LIBWING

/*Some useful things*/

#ifdef __cplusplus
extern "C" {
#endif

/*On Win32, globs pattern and invokes func(name, env) for each file found.
    When func returns nonzero OR all matching files have been processed,
    returns the number of files processed.  (If wing_glob_foreach returns
    0, no files matched the glob.)
  Returns -1 if an error occurrs in the glob processing.
  On *nix (where the shell does globbing for us), invokes func(pattern, env)
    and returns 1.
  func should use env (or global storage) to report success/failure status
    back to the caller.
*/
int wing_glob_foreach(const char *pattern, int (*func)(const char *name, void *env), void *env);

#ifdef __cplusplus
}
#endif

#endif
