#!awk -f

#Munch comments
$1 ~ /^#/ { next; }

#Global arrays:
#  toolchains[toolchain_name] = platform for toolchain
#  modules[module_name] = type (also serves as list of all known modules)
#  sources[module, platform, type] = list of sources for module grouped
#                                    by platform and type
#  mod_platforms[module_name, platform] = 1 (list of module/platforms)
#  templates[toolchain, type] = templates for output filenames
#  suffixes[type] = almost-ERE matching extension for input filenames
#                   (the ERE is formed by gsub("\\.","\\.",suffix) and then
#                   using "("suffix")$".)
#  rules[mod_type] = Base name of build rule ("link" or "ar" are currently
#                    known) to build modules of that type

# TODO: Make configurable
BEGIN {
	rules["program"] = "link";
	rules["library"] = "ar";
}

$1 == "suffix" {
	if($2 in suffixes) {
		print FILENAME ":" FNR ": Warning: Replacing previously defined suffixes for filetype '" $2 "'" >> "/dev/stderr";
	}
	suffixes[$2] = $3;
	for(i=4; i<=NF; i++) {
		suffixes[$2] = suffixes[$2] "|" $i;
	}
}

$1 == "template" {
	if(($2,$3) in templates) {
		print FILENAME ":" FNR ": Warning: Replacing previously defined template for toolchain '" $2 "', filetype '" $3 "'" >> "/dev/stderr";
	}
	templates[$2,$3] = $4;
	for(i=5; i<=NF; i++) {
		templates[$2,$3] = templates[$2,$3] " " $i;
	}
}

function get_base_name(type, name) {
	if(type in suffixes) {
		suffix = suffixes[type];
		gsub("\\.", "\\.", suffix);
		gsub("("suffix")$", "", name);
	}
	return name;
}

function get_out_name(toolchain, type, base) {
	if((toolchain, type) in templates) {
		retval = templates[toolchain, type];
		gsub("%", base, retval);
		return retval;
	}
	if(("all", type) in templates) {
		retval = templates["all", type];
		gsub("%", base, retval);
		return retval;
	}
	if(type in suffixes) {
		#If there are multiple suffixes allowed, assume the first
		#  one is preferred
		suffix = suffixes[type];
		sub("\\|.*", "", suffix);
		return base suffix;
	}
	return base;
}

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
	if(!($1 in rules)) {
		print FILENAME ":" FNR ": Module " $2 " has unknown type '"$1"'" >> "/dev/stderr";
		fail=1;
	}
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
		print FILENAME ":" FNR ": Module " $2 " was previously named with type " modules[$2] >> "/dev/stderr";
		fail = 1;
	}
}

function get_sources(module, platform, type) {
	return sources[module, "all", type] " " sources[module, platform, type];
}

function write_rules(toolchain) {
	platform = toolchains[toolchain];

	local_programs = "";

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
			basename = get_base_name("C", local_srcs[i]);
			objname = get_out_name(toolchain, "obj", toolchain "/" basename);
			print "build " objname " : " toolchain "cc " local_srcs[i];
			local_inputsbytype["obj"] = local_inputsbytype["obj"] " " objname;
			local_linkinputs = local_linkinputs " " objname;
		}
		n = split(get_sources(module, platform, "library"), local_srcs, " ");
		for (i=1; i<=n; i++) {
			libname = get_out_name(toolchain, "library", toolchain "/" local_srcs[i]);
			local_linkinputs = local_linkinputs " " libname;
			local_inputsbytype["library"] = local_inputsbytype["library"] " " libname;
		}

		outname = get_out_name(toolchain, modules[module], toolchain "/" module);
		rule = toolchain rules[modules[module]];
		print "build " outname " : " rule local_linkinputs;
		print " out_base = " toolchain "/" module;
		for (type in local_inputsbytype) {
			print " in_" type " =" local_inputsbytype[type];
		}

		if (modules[module] == "program") {
			local_programs = local_programs " " outname;
		}
	}
	if (local_programs != "") {
		print "build " toolchain " : phony" local_programs;
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
