#!awk -f

#Munch comments
$1 ~ /^#/ { next; }

#Global arrays:
#  toolchains[toolchain_name] = platform for toolchain

#Toolchains
# $2 = toolchain name
# $3 = platform
# $4 = subplatform
# $5 = bitness
$1 == "toolchain" {
	toolchains[$2] = $3;
	# TODO: Be more selective in next rule (collect names) so we don't
	# have to do this here
	next;
}

#Collect names of things
{
	modules[$2] = 1;
	srctypes[$5] = 1;
	platforms[$4] = 1;
}

#Collect sources
($3 == "source") {
	module = $2;
	platform = $4;
	type = $5;
	module_sourcetypes[module, type] = 1;
	module_platforms[module, platform] = 1;
	for (i=6; i<=NF; i++) {
		old = sources[module, platform, type];
		sources[module, platform, type] = old " " $i;
	}
}

#Collect module types and sanity-check
{
	if (!($2 in modtypes)) {
		modtypes[$2] = $1;
	}
	if (modtypes[$2] != $1) {
		print FILENAME ":" FNR ": Module " $2 " was previously named with type " modtypes[$2];
		fail = 1;
	}
}

function write_rules(toolchain) {
	for (module in modules) {
		local_linkinputs = "";
		n = split(sources[module, "all", "C"], local_srcs, " ");
		for (i=1; i<=n; i++) {
			# sub substitutes in-place
			objname = local_srcs[i];
			sub(/\.c$/, ".o", objname);
			print "build " toolchain "/" objname " : " toolchain "cc " local_srcs[i];
			local_linkinputs = local_linkinputs " " toolchain "/" objname;
		}
		n = split(sources[module, "all", "library"], local_srcs, " ");
		for (i=1; i<=n; i++) {
			local_linkinputs = local_linkinputs " " toolchain "/" local_srcs[i] ".a";
		}
			
		if (modtypes[module] == "program") {
			print "build " toolchain "/" module " : " toolchain "link" local_linkinputs;
		} else if (modtypes[module] == "library") {
			print "build " toolchain "/" module ".a : " toolchain "ar" local_linkinputs;
		} else {
			print "--ERROR-- Unknown module type '" modtypes[module] "'";
		}
	}
}

END {
	if (fail) {
		exit 1;
	}

	#Toolchain notes:
	#mingw (and Win32 toolchains in general) need to know to put
	# a '.exe' suffix on programs.
	#winegcc requires more general pattern-matching, since when given
	# '-o foo' to create an executable it actually creates two files,
	# foo.exe and foo.exe.so (so the build line writer needs to write
	# both output files, and give a 'base_name = foo' for the rule to
	# use.
	#Toolchain-specific name generation for things like object files
	# and libraries is also required before we're ready for prime time.
	for (tc in toolchains) {
		write_rules(tc);
	}
}
