# -----------------------------------------------------------------------------
#         _   _             _ 
#   _____| |_| |_ _____ ___| |
#  |     | '_|  _|     | . | |
#  |_|_|_|_,_|_| |_|_|_|  _|_|
#                      |_|    
#
# -----------------------------------------------------------------------------
#
# `maketmpl` is a `make`-based template generation tool. It takes a  
# project definition defined in the `tmpl` directory, detects any
# variable in the names (like `{VARIABLE_NAME}.txt`) as well as 
# variables defined in the content of any file ending in `.mktmpl`.

# TODO: Test that tmpl exists, if not, fail.
# TODO: Make sure all the configuration variables are defined on apply

EDITOR                 ?=vi

# The file containing the definitions of the configuration variables. Should
# not exist by default.
TEMPLATE_CONF          ?=Makefile.conf

# The path where the templates are located
TEMPLATE_EXT           ?=.tmpl

# The path where the template files are located
TEMPLATE_PATH          ?=tmpl

# The path where the current template files will be backed up
TEMPLATE_BACKUP_PATH   ?=.tmpl

# The template application post script
TEMPLATE_POST          ?=mktmpl.post.sh

# The distribution directory where the files will be built/copied
PRODUCT_PATH           ?=.dist


# -----------------------------------------------------------------------------
# 
# TEMPLATE INTROSPECTION
#
# -----------------------------------------------------------------------------

# Contains all the FILES in the template path
TEMPLATE_MANIFEST    :=$(filter-out $(TEMPLATE_PATH)/$(TEMPLATE_POST),$(shell find $(TEMPLATE_PATH) -name "*"))
# The DIRECTORIES whose name have a TEMPLATE EXPRESSION
TEMPLATE_TMPL_DIRS   :=$(shell find $(TEMPLATE_PATH) -regextype egrep -type d -regex '^(.*)?{[A-Z]+}(.*)$$' | sed 's|\./||g')
# The FILES whose names have a TEMPLATE EXPRESSION
TEMPLATE_TMPL_FILES  :=$(filter-out $(TEMPLATE_PATH)/$(TEMPLATE_POST),$(shell find $(TEMPLATE_PATH) -regextype egrep -type f -regex '^(.*)?{[A-Z]+}(.*)$$' | sed 's|\./||g'))
# The files which CONTENT have TEMPLATE EXPRESSIONS
TEMPLATE_TMPL_CONTENT:=$(shell find $(TEMPLATE_PATH) -name "*$(TEMPLATE_EXT)")
# These are the files in the manifest that are not DIRS, FILES or CONTENT templates (ie. REGULAR files)
TEMPLATE_TMPL_REGULAR:=$(shell echo $(TEMPLATE_MANIFEST) | xargs -n1 echo | grep -v -e ".*\$(TEMPLATE_EXT)" -e ".*{[A-Z]\\+}.*")
# NOTE: The maxdepth here is brittle, as it depends on
TEMPLATE_SCRIPT      :=$(shell ls $(TEMPLATE_PATH)/ | grep  "$(TEMPLATE_POST)")

# Greps the TEMPLATE VARIABLE NAMES from the template dirs and file names
TEMPLATE_VARS        :=$(strip $(shell echo $(TEMPLATE_TMPL_DIRS) $(TEMPLATE_TMPL_FILES) | egrep -o '\{([A-Z]+)\}' | tr -d '{}' | sort | uniq))
# Identifies which templates variables are set
TEMPLATE_VARS_SET    :=$(strip $(shell test -e $(TEMPLATE_CONF) && egrep -o '^\s*[A-Z]*\s*:=\s*[^ \t].*' $(TEMPLATE_CONF) | cut -d: -f1 | sort | uniq))

PRODUCT_TMPL_REGULAR :=$(TEMPLATE_TMPL_REGULAR:$(TEMPLATE_PATH)/%=$(PRODUCT_PATH)/%)
PRODUCT_TMPL_CONTENT :=$(TEMPLATE_TMPL_CONTENT:$(TEMPLATE_PATH)/%$(TEMPLATE_EXT)=$(PRODUCT_PATH)/%)
PRODUCT_TMPL_FILES   :=$(TEMPLATE_TMPL_FILES:$(TEMPLATE_PATH)/%=$(PRODUCT_PATH)/%)
PRODUCT_TMPL_DIRS    :=$(TEMPLATE_TMPL_DIRS:$(TEMPLATE_PATH)/%=$(PRODUCT_PATH)/%)
PRODUCT_TMPL_ALL     :=$(filter-out $(TEMPLATE_PATH)%, \
    $(PRODUCT_TMPL_REGULAR) $(PRODUCT_TMPL_CONTENT) $(PRODUCT_TMPL_FILES) $(PRODUCT_TMPL_DIRS))

# -----------------------------------------------------------------------------
# 
# COLORS
#
# -----------------------------------------------------------------------------

YELLOW         :=$(shell tput setaf 226)
ORANGE         :=$(shell tput setaf 208)
GREEN          :=$(shell tput setaf 118)
BLUE           :=$(shell tput setaf 45)
CYAN           :=$(shell tput setaf 51)
RED            :=$(shell tput setaf 196)
GRAY           :=$(shell tput setaf 153)
GRAYLT         :=$(shell tput setaf 231)
RESET          :=$(shell tput sgr0)
BOLD           :=$(shell tput bold)
UNDERLINE      :=$(shell tput smul)
REGULAR        :=$(shell echo '\033[0m')
REV            :=$(shell tput rev)
DIM            :=$(shell tput dim)

# -----------------------------------------------------------------------------
# 
# META-PROGRAMMING
#
# -----------------------------------------------------------------------------
# This section generates rules for each of the TEMPLATE_{DIRS|FILES|CONTENT}
# based on the TEMPLATE_CONF values.

PRODUCT_TEMPLATE_TMPL_DIRS         =$(TEMPLATE_TMPL_DIRS:$(TEMPLATE_PATH)/%=%)
PRODUCT_TEMPLATE_TMPL_FILES        =$(TEMPLATE_TMPL_FILES:$(TEMPLATE_PATH)/%=%)
PRODUCT_TEMPLATE_TMPL_CONTENT      =$(TEMPLATE_TMPL_CONTENT:$(TEMPLATE_PATH)/%$(TEMPLATE_EXT)=%)

# If all the template variables are set
ifeq ($(TEMPLATE_VARS),$(TEMPLATE_VARS_SET))
	TEMPLATE_VARS_COMPLETE:=true
	# We load the values of all the variables
	include $(TEMPLATE_CONF)
	# We create a `sed` expression to replace '{A-Z}` with the variablee content
	TEMPLATE_SED:=$(foreach var,$(TEMPLATE_VARS),s|{$(strip $(var))}|$(value $(var))|g;)
	PRODUCT_ALL:=$(shell echo $(PRODUCT_TMPL_ALL) | xargs -n1 echo | sed '$(TEMPLATE_SED)')
# Meta rule create a file from the templates
define MAKE_TEMPLATE_FILE_RULE =

$(PRODUCT_PATH)/$(patsubst $(TEMPLATE_PATH)/%,%,$(patsubst %$(TEMPLATE_EXT),%,$(strip $(shell echo $(1) | sed '$(TEMPLATE_SED)')))): $(1)
	@echo "$(GREEN) ◀  $(BOLD)$$@$(RESET) ← $$^ $(BLUE)[TEMPLATE FILE]$(RESET)"
	@if [ -d "$$<" ]; then mkdir -p "$$@" ; else mkdir -p `dirname "$$@"` && cp -a "$$<" "$$@" ; fi
endef
#
# Meta rule create a file from the templates
define MAKE_TEMPLATE_CONTENT_RULE =

$(PRODUCT_PATH)/$(patsubst $(TEMPLATE_PATH)/%,%,$(patsubst %$(TEMPLATE_EXT),%,$(strip $(shell echo $(1) | sed '$(TEMPLATE_SED)')))): $(1)
	@echo "$(GREEN) ◀  $(BOLD)$$@$(RESET) ← $$^ $(BLUE)[TEMPLATE CONTENT]$(RESET)"
	@mkdir -p `dirname "$$@"`
	@cat "$$<" | sed '$(TEMPLATE_SED)' > "$$@"
	@cp --attributes-only "$$<" "$$@"

endef

# Meta rule create a directory from the templates
define MAKE_TEMPLATE_DIR_RULE =

$(PRODUCT_PATH)/$(patsubst $(TEMPLATE_PATH)/%,%,$(strip $(shell echo $(1) | sed '$(TEMPLATE_SED)'))): $(1)
	@echo "$(GREEN) ◀  $(BOLD)$$@$(RESET) ← $$^ $(BLUE)[TEMPLATE DIR]$(RESET)"
	@mkdir -p "$$@"

endef

define MAKE_TEMPLATE =
#-- FILES WITH TEMPLATE NAMES
#== $(TEMPLATE_TMPL_FILES)
$(foreach file,$(TEMPLATE_TMPL_FILES),$(call MAKE_TEMPLATE_FILE_RULE,$(file)))
#-- FILES WITH TEMPLATE CONTENT
#== $(TEMPLATE_TMPL_CONTENT)
$(foreach file,$(TEMPLATE_TMPL_CONTENT),$(call MAKE_TEMPLATE_CONTENT_RULE,$(file)))
#-- DIRS WITH TEMPLATE NAMES
#== $(TEMPLATE_TMPL_DIRS)
$(foreach file,$(TEMPLATE_TMPL_DIRS),$(call MAKE_TEMPLATE_DIR_RULE,$(file)))
#-- REGULAR FILES
#== $(TEMPLATE_TMPL_REGULAR)
$(foreach file,$(TEMPLATE_TMPL_REGULAR),$(call MAKE_TEMPLATE_FILE_RULE,$(file)))
endef
else
ERR_CONFIG_MISSING=1
endif

# -----------------------------------------------------------------------------
# 
# RULES
#
# -----------------------------------------------------------------------------

.PHONY: all apply help config configuration mf manifest vars variables meta

help:
	@echo "$(BOLD)MKTMPL$(RESET) ― Makefile-based template generation"
	@echo "make $(BOLD)$(YELLOW)apply$(RESET)    ― applies the template in $(CYAN)$(TEMPLATE_PATH)$(RESET) to $(CYAN)$(PRODUCT_PATH)$(RESET)"
	@echo "make $(BOLD)$(YELLOW)config$(RESET)   ― edits the configuration file $(CYAN)$(TEMPLATE_CONF)$(RESET)"
	@echo "make $(BOLD)$(YELLOW)manifest$(RESET) ― lists all the files that will be created by $(YELLOW)apply$(RESET)"

# This ensures that the template configuration exists and succee
all: apply cleanup
	
# Outputs the list of files  that will be created by applying the template
manifest:
	@echo $(PRODUCT_TMPL_ALL) | xargs -n1 echo | sed '$(TEMPLATE_SED)' | sort
	@if [ "$(ERR_CONFIG_MISSING)" == "1" ]; then echo "$(RED)$(BOLD)[!] $(RESET)$(RED)No configuration file found$(RESET), run $(YELLOW)make $(BOLD)config$(RESET) to create it"; fi

manifest-raw:
	@echo $(PRODUCT_TMPL_ALL) | xargs -n1 echo | sort

# Ensures that the configuration file exists and is properly filled-in
# TODO: We might want to check that all the variables are set
configuration: $(TEMPLATE_CONF)

# Applies the configuration and generates the template files
apply: configuration $(PRODUCT_ALL)
	@echo "$(YELLOW)$(BOLD) "
	@echo "          _   _             _ "
	@echo "    _____| |_| |_ _____ ___| |"
	@echo "   |     | '_|  _|     | . | |"
	@echo "   |_|_|_|_,_|_| |_|_|_|  _|_|"
	@echo "                    |_|"
	@echo "$(RESET) "
	@if [ -n "$(PRODUCT_ALL)" ]; then \
		echo "$(CYAN) ◆  [apply] Applied templates:$(RESET)"; \
		echo $(PRODUCT_ALL) | xargs -n1 echo "   " | sed '$(TEMPLATE_SED)' | sort; \
	fi
	@if [ -n "$(TEMPLATE_SCRIPT)" ]; then \
		echo "$(CYAN) ◆  [apply] Running post-apply script: $(PRODUCT_PATH)/$(TEMPLATE_SCRIPT)$(RESET)"; \
		cp -a "$(TEMPLATE_PATH)/$(TEMPLATE_SCRIPT)" "$(PRODUCT_PATH)/$(TEMPLATE_SCRIPT)"; \
		sed -i '$(TEMPLATE_SED)' "$(PRODUCT_PATH)/$(TEMPLATE_SCRIPT)"; \
		pushd "$(PRODUCT_PATH)" ; bash ./$(TEMPLATE_SCRIPT) ; unlink ./$(TEMPLATE_SCRIPT); popd; \
	fi

unapply:
	@if [ -d "$(PRODUCT_PATH)" ]; then rm -rf "$(PRODUCT_PATH)"; fi

cleanup:
	@if [ ! -d "$(TEMPLATE_BACKUP_PATH)" ]; then mkdir $(TEMPLATE_BACKUP_PATH); fi
	@mv Makefil* README.md "$(TEMPLATE_PATH)" "$(TEMPLATE_BACKUP_PATH)"
	@find "$(PRODUCT_PATH)" -maxdepth 1 -name "*" -not -name "$(PRODUCT_PATH)" -exec mv '{}' . ';'
	@rmdir "$(PRODUCT_PATH)"

revert:
	if [ -d "../$(TEMPLATE_BACKUP_PATH)" ]; then \
		test -d "$(PRODUCT_PATH)" || mkdir -p "$(PRODUCT_PATH)"; \
	 	find .. -maxdepth 1 -name "*" -not -name ".." -not -name "$(TEMPLATE_BACKUP_PATH)" -not -name "$(PRODUCT_PATH)" -exec mv '{}' "$(PRODUCT_PATH)" ';' ; \
		mv Makefil* README.md $(TEMPLATE_PATH) $(PRODUCT_PATH) .. ; \
	fi 

# Lists the variables defined in the template
variables:
	@echo $(TEMPLATE_VARS)

config: configuration
	
mf: manifest
	
vars: variables
	
rules:
	$(info $(SED_TEMPLATE))
	$(info $(MAKE_TEMPLATE))

# -----------------------------------------------------------------------------
# 
# PRODUCTION RULES
#
# -----------------------------------------------------------------------------


# This is the production rule that creates the template configuration file
$(TEMPLATE_CONF):
	@echo "$(GREEN) ◀  $(BOLD)$$@$(RESET) $(BLUE)[TEMPLATE CONF]$(RESET)"
	@echo "# Fill the given variables to create the project" > $@
	@for VAR in $(TEMPLATE_VARS);\
		do\
			echo $$VAR := >> $@; \
		done
	@$(EDITOR) $@
	@make apply

# This is the production rule that expands a template into its target file.
$(PRODUCT_PATH)/%: $(TEMPLATE_PATH)/%$(TEMPLATE_EXT)
	@echo "$(GREEN) ◀  $(BOLD)$$@$(RESET) ← $$^ $(BLUE)[TEMPLATE PATH]$(RESET)"
	@mkdir -p `dirname "$@"`
	@cat $< | sed '$(TEMPLATE_SED)' > $@

# === HELPERS =================================================================

print-%:
	@echo "$*="
	@echo "$($*)" | xargs -n1 echo | sort -dr

# Adds the dynamically generated rules
$(eval $(MAKE_TEMPLATE))

# EOF
