#include <windows.h>

#include <stdio.h>

#include "libwing.h"

int wing_glob_foreach(const char *pattern, int (*func)(const char *name, void *env), void *env)
{
	int count=0;
	WIN32_FIND_DATA fd;
	HANDLE h;
	DWORD err;

	h=FindFirstFile(pattern, &fd);

	if(h==INVALID_HANDLE_VALUE)
	{
		err=GetLastError();
		if(err == ERROR_FILE_NOT_FOUND)
			return 0;
		/*TODO: Proper error reporting (program name, and friendly
		  error description)
		*/
		fprintf(stderr, "wing_glob_foreach: FindFirstFile failed: %lu\n", (unsigned long)err);
		return -1;
	}

	do
	{
		int ret=func(fd.cFileName, env);
		count++;
		if(ret != 0)
			break;
	}
	while(FindNextFile(h, &fd) != 0);

	err=GetLastError();
	if(err == ERROR_NO_MORE_FILES)
		return count;
	/*TODO: Proper error reporting (program name, and friendly
	  error description)
	*/
	fprintf(stderr, "wing_glob_foreach: FindFirstFile failed: %lu\n", (unsigned long)err);
	return -1;
}
