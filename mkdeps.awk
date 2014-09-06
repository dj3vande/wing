#!awk -f

#Munch comments
$1 ~ /^#/ { next; }

#Global arrays:
#  toolchains[toolchain_name] = platform for toolchain
#  modules[module_name] = type (also serves as list of all known modules)
#  sources[module, platform, type] = list of sources for module grouped
#                                    by platform and type
#  mod_platforms[module_name, platform] = 1 (list of module/platforms)

#Toolchains
# $2 = toolchain name
# $3 = platform
# $4 = subplatform
# $5 = bitness
$1 == "toolchain" {
	toolchains[$2] = $3;
}

#Collect sources
($3 == "source") {
	module = $2;
	platform = $4;
	type = $5;
	mod_platforms[module, platform] = 1;
	for (i=6; i<=NF; i++) {
		old = sources[module, platform, type];
		sources[module, platform, type] = old " " $i;
	}
}

#Collect module types and sanity-check
($1 == "program") || ($1 == "library") {
	if (!($2 in modules)) {
		modules[$2] = $1;
	}
	if (modules[$2] != $1) {
		print FILENAME ":" FNR ": Module " $2 " was previously named with type " modules[$2];
		fail = 1;
	}
}

function get_sources(module, platform, type) {
	return sources[module, "all", type] " " sources[module, platform, type];
}

function write_rules(toolchain) {
	platform = toolchains[toolchain];
	for (module in modules) {
		if (!((module, "all") in mod_platforms || (module, platform) in mod_platforms)) {
			continue;
		}

		#Clear out inputs-by-type array, without breaking if it
		# doesn't yet exist as an array
		local_inputsbytype[""]="";
		for(type in local_inputsbytype) {
			delete local_inputsbytype[type];
		}

		local_linkinputs = "";
		n = split(get_sources(module, platform, "C"), local_srcs, " ");
		for (i=1; i<=n; i++) {
			# sub substitutes in-place
			objname = toolchain "/" local_srcs[i];
			sub(/\.c$/, ".o", objname);
			print "build " objname " : " toolchain "cc " local_srcs[i];
			local_inputsbytype["obj"] = local_inputsbytype["obj"] " " objname;
			local_linkinputs = local_linkinputs " " objname;
		}
		n = split(get_sources(module, platform, "library"), local_srcs, " ");
		for (i=1; i<=n; i++) {
			libname = toolchain "/" local_srcs[i] ".a";
			local_linkinputs = local_linkinputs " " libname;
			local_inputsbytype["lib"] = local_inputsbytype["lib"] " " libname;
		}

		if (modules[module] == "program") {
			print "build " toolchain "/" module " : " toolchain "link" local_linkinputs;
		} else if (modules[module] == "library") {
			print "build " toolchain "/" module ".a : " toolchain "ar" local_linkinputs;
		} else {
			print "--ERROR-- Unknown module type '" modules[module] "'";
		}
		for (type in local_inputsbytype) {
			print " in_" type " =" local_inputsbytype[type];
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
