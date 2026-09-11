default:

release-%:
	TMP_PROJECT="$(shell mktemp -d)/Project.toml" && \
	touch $${TMP_PROJECT} && \
	JULIA_LOAD_PATH="$${TMP_PROJECT}:" JULIA_PROJECT="" \
	julia -e '                                                             \
	    import Pkg;                                                        \
	    Pkg.add("PkgDev"); Pkg.develop(path=pwd());                        \
	    import PkgDev;                                                     \
	    PkgDev.tag("LanguageServer", :$*; credentials=ENV["GITHUB_TOKEN"]) \
	'
