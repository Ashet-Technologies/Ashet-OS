/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 Erwan Velu - All Rights Reserved
 *
 *   Permission is hereby granted, free of charge, to any person
 *   obtaining a copy of this software and associated documentation
 *   files (the "Software"), to deal in the Software without
 *   restriction, including without limitation the rights to use,
 *   copy, modify, merge, publish, distribute, sublicense, and/or
 *   sell copies of the Software, and to permit persons to whom
 *   the Software is furnished to do so, subject to the following
 *   conditions:
 *
 *   The above copyright notice and this permission notice shall
 *   be included in all copies or substantial portions of the Software.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 *   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 *   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 *   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *   OTHER DEALINGS IN THE SOFTWARE.
 *
 * -----------------------------------------------------------------------
 */

#include <stdlib.h>
#include <string.h>
#include <syslinux/config.h>
#include <getkey.h>
#include <acpi/acpi.h>
#include "hdt-cli.h"
#include "hdt-common.h"

struct cli_mode_descr *list_modes[] = {
    &hdt_mode,
    &dmi_mode,
    &syslinux_mode,
    &pxe_mode,
    &kernel_mode,
    &cpu_mode,
    &pci_mode,
    &vesa_mode,
    &disk_mode,
    &vpd_mode,
    &memory_mode,
    &acpi_mode,
    NULL,
};

/*
 * .aliases = {"q", "quit"} won't work since it is an array of pointers, not an
 * array of variables. There is no easy way around it besides declaring the arrays of
 * strings first.
 */
const char *exit_aliases[] = { "q", "quit" };
const char *help_aliases[] = { "h", "?" };

/* List of aliases */
struct cli_alias hdt_aliases[] = {
    {
     .command = CLI_EXIT,
     .nb_aliases = 2,
     .aliases = exit_aliases,
     },
    {
     .command = CLI_HELP,
     .nb_aliases = 2,
     .aliases = help_aliases,
     },
};

struct cli_mode_descr *current_mode;
int autocomplete_backlog;

struct autocomplete_list {
    char autocomplete_token[MAX_LINE_SIZE];
    struct autocomplete_list *next;
};
struct autocomplete_list *autocomplete_head = NULL;
struct autocomplete_list *autocomplete_tail = NULL;
struct autocomplete_list *autocomplete_last_seen = NULL;

static void autocomplete_add_token_to_list(const char *token)
{
    struct autocomplete_list *new = malloc(sizeof(struct autocomplete_list));

    strlcpy(new->autocomplete_token, token, sizeof(new->autocomplete_token));
    new->next = NULL;
    autocomplete_backlog++;

    if (autocomplete_tail != NULL)
	autocomplete_tail->next = new;
    if (autocomplete_head == NULL)
	autocomplete_head = new;
    autocomplete_tail = new;
}

static void autocomplete_destroy_list(void)
{
    struct autocomplete_list *tmp = NULL;

    while (autocomplete_head != NULL) {
	tmp = autocomplete_head->next;
	free(autocomplete_head);
	autocomplete_head = tmp;
    }
    autocomplete_backlog = 0;
    autocomplete_tail = NULL;
    autocomplete_last_seen = NULL;
}

/**
 * set_mode - set the current mode of the cli
 * @mode:	mode to set
 *
 * Unlike cli_set_mode, this function is not used by the cli directly.
 **/
void set_mode(cli_mode_t mode, struct s_hardware *hardware)
{
    int i = 0;

    switch (mode) {
    case EXIT_MODE:
	hdt_cli.mode = mode;
	break;
    case HDT_MODE:
	hdt_cli.mode = mode;
	snprintf(hdt_cli.prompt, sizeof(hdt_cli.prompt), "%s> ", CLI_HDT);
	break;
    case PXE_MODE:
	if (hardware->sv->filesystem != SYSLINUX_FS_PXELINUX) {
	    more_printf("You are not currently using PXELINUX\n");
	    break;
	}
	hdt_cli.mode = mode;
	snprintf(hdt_cli.prompt, sizeof(hdt_cli.prompt), "%s> ", CLI_PXE);
	break;
    case KERNEL_MODE:
	hdt_cli.mode = mode;
	snprintf(hdt_cli.prompt, sizeof(hdt_cli.prompt), "%s> ", CLI_KERNEL);
	break;
    case SYSLINUX_MODE:
	hdt_cli.mode = mode;
	snprintf(hdt_cli.prompt, sizeof(hdt_cli.prompt), "%s> ", CLI_SYSLINUX);
	break;
    case VESA_MODE:
	hdt_cli.mode = mode;
	snprintf(hdt_cli.prompt, sizeof(hdt_cli.prompt), "%s> ", CLI_VESA);
	break;
    case PCI_MODE:
	hdt_cli.mode = mode;
	snprintf(hdt_cli.prompt, sizeof(hdt_cli.prompt), "%s> ", CLI_PCI);
	break;
    case CPU_MODE:
	hdt_cli.mode = mode;
	snprintf(hdt_cli.prompt, sizeof(hdt_cli.prompt), "%s> ", CLI_CPU);
	break;
    case DMI_MODE:
	if (!hardware->is_dmi_valid) {
	    more_printf("No valid DMI table found, exiting.\n");
	    break;
	}
	hdt_cli.mode = mode;
	snprintf(hdt_cli.prompt, sizeof(hdt_cli.prompt), "%s> ", CLI_DMI);
	break;
    case DISK_MODE:
	hdt_cli.mode = mode;
	snprintf(hdt_cli.prompt, sizeof(hdt_cli.prompt), "%s> ", CLI_DISK);
	break;
    case VPD_MODE:
	if (!hardware->is_vpd_valid) {
	    more_printf("No valid VPD table found, exiting.\n");
	    break;
	}
	hdt_cli.mode = mode;
	snprintf(hdt_cli.prompt, sizeof(hdt_cli.prompt), "%s> ", CLI_VPD);
	break;
    case MEMORY_MODE:
	hdt_cli.mode = mode;
	snprintf(hdt_cli.prompt, sizeof(hdt_cli.prompt), "%s> ", CLI_MEMORY);
	break;
    case ACPI_MODE:
	hdt_cli.mode = mode;
	snprintf(hdt_cli.prompt, sizeof(hdt_cli.prompt), "%s> ", CLI_ACPI);
	break;
    default:
	/* Invalid mode */
	more_printf("Unknown mode, please choose among:\n");
	while (list_modes[i]) {
	    more_printf("\t%s\n", list_modes[i]->name);
	    i++;
	}
    }

    find_cli_mode_descr(hdt_cli.mode, &current_mode);
    /* There is not cli_mode_descr struct for the exit mode */
    if (current_mode == NULL && hdt_cli.mode != EXIT_MODE) {
	/* Shouldn't get here... */
	more_printf("!!! BUG: Mode '%d' unknown.\n", hdt_cli.mode);
    }
}

/**
 * mode_s_to_mode_t - given a mode string, return the cli_mode_t representation
 **/
cli_mode_t mode_s_to_mode_t(char *name)
{
    int i = 0;

    while (list_modes[i]) {
	if (!strncmp(name, list_modes[i]->name, sizeof(list_modes[i]->name)))
	    break;
	i++;
    }

    if (!list_modes[i])
	return INVALID_MODE;
    else
	return list_modes[i]->mode;
}

/**
 * find_cli_mode_descr - find the cli_mode_descr struct associated to a mode
 * @mode:	mode to look for
 * @mode_found:	store the mode if found, NULL otherwise
 *
 * Given a mode name, return a pointer to the associated cli_mode_descr
 * structure.
 * Note: the current mode name is stored in hdt_cli.mode.
 **/
void find_cli_mode_descr(cli_mode_t mode, struct cli_mode_descr **mode_found)
{
    int i = 0;

    while (list_modes[i] && list_modes[i]->mode != mode)
	i++;

    /* Shouldn't get here... */
    if (!list_modes[i])
	*mode_found = NULL;
    else
	*mode_found = list_modes[i];
}

/**
 * expand_aliases - resolve aliases mapping
 * @line:	command line to parse
 * @command:	first token in the line
 * @module:	second token in the line
 * @argc:	number of arguments
 * @argv:	array of arguments
 *
 * We maintain a small list of static alises to enhance user experience.
 * Only commands can be aliased (first token). Otherwise it can become really hairy...
 **/
static void expand_aliases(char *line __unused, char **command, char **module,
			   int *argc, char **argv)
{
    struct cli_mode_descr *mode;
    int i, j;

    find_cli_mode_descr(mode_s_to_mode_t(*command), &mode);
    if (mode != NULL && *module == NULL) {
	/*
	 * The user specified a mode instead of `set mode...', e.g.
	 * `dmi' instead of `set mode dmi'
	 */

	/* *argv is NULL since *module is NULL */
	*argc = 1;
	*argv = malloc(*argc * sizeof(char *));
	argv[0] = malloc((sizeof(*command) + 1) * sizeof(char));
	strlcpy(argv[0], *command, sizeof(*command) + 1);
	dprintf("CLI DEBUG: ALIAS %s ", *command);

	strlcpy(*command, CLI_SET, sizeof(CLI_SET));	/* set */

	*module = malloc(sizeof(CLI_MODE) * sizeof(char));
	strlcpy(*module, CLI_MODE, sizeof(CLI_MODE));	/* mode */

	dprintf("--> %s %s %s\n", *command, *module, argv[0]);
	goto out;
    }

    /* Simple aliases mapping a single command to another one */
    for (i = 0; i < MAX_ALIASES; i++) {
	for (j = 0; j < hdt_aliases[i].nb_aliases; j++) {
	    if (!strncmp(*command, hdt_aliases[i].aliases[j],
			 sizeof(hdt_aliases[i].aliases[j]))) {
		dprintf("CLI DEBUG: ALIAS %s ", *command);
		strlcpy(*command, hdt_aliases[i].command,
			sizeof(hdt_aliases[i].command) + 1);
		dprintf("--> %s\n", *command);
		goto out;	/* Don't allow chaining aliases */
	    }
	}
    }
    return;

out:
    dprintf("CLI DEBUG: New parameters:\n");
    dprintf("CLI DEBUG: command = %s\n", *command);
    dprintf("CLI DEBUG: module  = %s\n", *module);
    dprintf("CLI DEBUG: argc    = %d\n", *argc);
    for (i = 0; i < *argc; i++)
	dprintf("CLI DEBUG: argv[%d] = %s\n", i, argv[0]);
    return;
}

/**
 * parse_command_line - low level parser for the command line
 * @line:	command line to parse
 * @command:	first token in the line
 * @module:	second token in the line
 * @argc:	number of arguments
 * @argv:	array of arguments
 *
 * The format of the command line is:
 *	<main command> [<module on which to operate> [<args>]]
 *	command is always malloc'ed (even for an empty line)
 **/
static void parse_command_line(char *line, char **command, char **module,
			       int *argc, char **argv)
{
    int argc_iter = 0, args_pos = 0, token_found = 0, token_len = 0;
    int args_len = 0;
    char *pch = NULL, *pch_next = NULL, *tmp_pch_next = NULL;

    *command = NULL;
    *module = NULL;
    *argc = 0;

    pch = line;
    while (pch != NULL) {
	pch_next = strchr(pch + 1, ' ');
	tmp_pch_next = pch_next;

	/*
	 * Skip whitespaces if the user entered
	 * 'set   mode        foo' for 'set mode foo'
	 *  ^   ^
	 *  |___|___ pch
	 *      |___ pch_next <- wrong!
	 *
	 *  We still keep the position into tmp_pch_next to compute
	 *  the lenght of the current token.
	 */
	while (pch_next != NULL && !strncmp(pch_next, CLI_SPACE, 1))
	    pch_next++;

	/* End of line guaranteed to be zeroed */
	if (pch_next == NULL) {
	    token_len = (int)(strchr(pch + 1, '\0') - pch);
	    args_len = token_len;
	} else {
	    token_len = (int)(tmp_pch_next - pch);
	    args_len = (int)(pch_next - pch);
	}

	if (token_found == 0) {
	    /* Main command to execute */
	    *command = malloc((token_len + 1) * sizeof(char));
	    strlcpy(*command, pch, token_len);
	    (*command)[token_len] = '\0';
	    dprintf("CLI DEBUG parse: command = %s\n", *command);
	    args_pos += args_len;
	} else if (token_found == 1) {
	    /* Module */
	    *module = malloc((token_len + 1) * sizeof(char));
	    strlcpy(*module, pch, token_len);
	    (*module)[token_len] = '\0';
	    dprintf("CLI DEBUG parse: module  = %s\n", *module);
	    args_pos += args_len;
	} else
	    (*argc)++;

	token_found++;
	pch = pch_next;
    }
    dprintf("CLI DEBUG parse: argc    = %d\n", *argc);

    /* Skip arguments handling if none is supplied */
    if (!*argc)
	return;

    /* Transform the arguments string into an array */
    *argv = malloc(*argc * sizeof(char *));
    pch = strtok(line + args_pos, CLI_SPACE);
    while (pch != NULL) {
	dprintf("CLI DEBUG parse: argv[%d] = %s\n", argc_iter, pch);
	argv[argc_iter] = malloc(strlen(pch) * sizeof(char));
	strlcpy(argv[argc_iter], pch, strlen(pch));
	argc_iter++;
	pch = strtok(NULL, CLI_SPACE);
	/*
	 * strtok(NULL, CLI_SPACE) over a stream of spaces
	 * will return an empty string
	 */
	while (pch != NULL && !strncmp(pch, "", 1))
	    pch = strtok(NULL, CLI_SPACE);
    }
}

/**
 * find_cli_callback_descr - find a callback in a list of modules
 * @module_name:	Name of the module to find
 * @modules_list:	Lits of modules among which to find @module_name
 * @module_found:	Pointer to the matched module, NULL if not found
 *
 * Given a module name and a list of possible modules, find the corresponding
 * module structure that matches the module name and store it in @module_found.
 **/
void find_cli_callback_descr(const char *module_name,
			     struct cli_module_descr *modules_list,
			     struct cli_callback_descr **module_found)
{
    int modules_iter = 0;

    if (modules_list == NULL)
	goto not_found;

    /* Find the callback to execute */
    while (modules_list->modules[modules_iter].name &&
	   strcmp(module_name, modules_list->modules[modules_iter].name) != 0)
	modules_iter++;

    if (modules_list->modules[modules_iter].name) {
	*module_found = &(modules_list->modules[modules_iter]);
	dprintf("CLI DEBUG: module %s found\n", (*module_found)->name);
	return;
    }

not_found:
    *module_found = NULL;
    return;
}

/**
 * autocomplete_command - print matching commands
 * @command:	Beginning of the command
 *
 * Given a string @command, print all availables commands starting with
 * @command. Commands are found within the list of commands for the current
 * mode and the hdt mode (if the current mode is not hdt).
 **/
static void autocomplete_command(char *command)
{
    int j = 0;
    struct cli_callback_descr *associated_module = NULL;

    /* First take care of the two special commands: 'show' and 'set' */
    if (strncmp(CLI_SHOW, command, strlen(command)) == 0) {
	printf("%s\n", CLI_SHOW);
	autocomplete_add_token_to_list(CLI_SHOW);
    }
    if (strncmp(CLI_SET, command, strlen(command)) == 0) {
	printf("%s\n", CLI_SET);
	autocomplete_add_token_to_list(CLI_SET);
    }

    /*
     * Then, go through the modes for the special case
     *      '<mode>' -> 'set mode <mode>'
     */
    while (list_modes[j]) {
	if (strncmp(list_modes[j]->name, command, strlen(command)) == 0) {
	    printf("%s\n", list_modes[j]->name);
	    autocomplete_add_token_to_list(list_modes[j]->name);
	}
	j++;
    }

    /*
     * Let's go now through the list of default_modules for the current mode
     * (single token commands for the current_mode)
     */
    j = 0;
    if (current_mode->default_modules && current_mode->default_modules->modules) {
	while (current_mode->default_modules->modules[j].name) {
	    if (strncmp(current_mode->default_modules->modules[j].name,
			command, strlen(command)) == 0) {
		printf("%s\n", current_mode->default_modules->modules[j].name);
		autocomplete_add_token_to_list(current_mode->default_modules->
					       modules[j].name);
	    }
	    j++;
	}
    }

    /*
     * Finally, if the current_mode is not hdt, list the available
     * default_modules of hdt (these are always available from any mode).
     */
    if (current_mode->mode == HDT_MODE)
	return;

    if (!hdt_mode.default_modules || !hdt_mode.default_modules->modules)
	return;

    j = 0;
    while (hdt_mode.default_modules &&
	   hdt_mode.default_modules->modules[j].name) {
	/*
	 * Any default command that is present in hdt mode but
	 * not in the current mode is available. A default
	 * command can be redefined in the current mode though.
	 * This next call tests this use case: if it is
	 * overwritten, do not print it again.
	 */
	find_cli_callback_descr(hdt_mode.default_modules->modules[j].name,
				current_mode->default_modules,
				&associated_module);
	if (associated_module == NULL &&
	    strncmp(command,
		    hdt_mode.default_modules->modules[j].name,
		    strlen(command)) == 0) {
	    printf("%s\n", hdt_mode.default_modules->modules[j].name);
	    autocomplete_add_token_to_list(hdt_mode.default_modules->modules[j].
					   name);
	}
	j++;
    }
}

/**
 * autocomplete_module - print matching modules
 * @command:	Command on the command line (not NULL)
 * @module:	Beginning of the module
 *
 * Given a command @command and a string @module, print all availables modules
 * starting with @module for command @command. Commands are found within the
 * list of commands for the current mode and the hdt mode (if the current mode
 * is not hdt).
 **/
static void autocomplete_module(char *command, char *module)
{
    int j = 0;
    char autocomplete_full_line[MAX_LINE_SIZE];

    if (strncmp(CLI_SHOW, command, strlen(command)) == 0) {
	if (!current_mode->show_modules || !current_mode->show_modules->modules)
	    return;

	while (current_mode->show_modules->modules[j].name) {
	    if (strncmp(current_mode->show_modules->modules[j].name,
			module, strlen(module)) == 0) {
		printf("%s\n", current_mode->show_modules->modules[j].name);
		sprintf(autocomplete_full_line, "%s %s",
			CLI_SHOW, current_mode->show_modules->modules[j].name);
		autocomplete_add_token_to_list(autocomplete_full_line);
	    }
	    j++;
	}
    } else if (strncmp(CLI_SET, command, strlen(command)) == 0) {
	j = 0;
	if (!current_mode->set_modules || !current_mode->set_modules->modules)
	    return;

	while (current_mode->set_modules->modules[j].name) {
	    if (strncmp(current_mode->set_modules->modules[j].name,
			module, strlen(module)) == 0) {
		printf("%s\n", current_mode->set_modules->modules[j].name);
		sprintf(autocomplete_full_line, "%s %s",
			CLI_SET, current_mode->set_modules->modules[j].name);
		autocomplete_add_token_to_list(autocomplete_full_line);
	    }
	    j++;
	}
    }
}

/**
 * autocomplete - find possible matches for a command line
 * @line:	command line to parse
 **/
static void autocomplete(char *line)
{
    int i;
    int argc = 0;
    char *command = NULL, *module = NULL;
    char **argv = NULL;

    parse_command_line(line, &command, &module, &argc, argv);

    dprintf("CLI DEBUG autocomplete: before checking args\n");
    /* If the user specified arguments, there is nothing we can complete */
    if (argc != 0)
	goto out;

    /* No argument, (the start of) a module has been specified */
    if (module != NULL) {
	autocomplete_module(command, module);
	free(module);
	goto out;
    }

    /* No argument, no module, (the start of) a command has been specified */
    if (command != NULL) {
	autocomplete_command(command);
	free(command);
	goto out;
    }

out:
    /* Let's not forget to clean ourselves */
    for (i = 0; i < argc; i++)
	free(argv[i]);
    if (argc > 0)
	free(argv);
    return;
}

/**
 * exec_command - main logic to map the command line to callbacks
 **/
static void exec_command(char *line, struct s_hardware *hardware)
{
    int argc, i = 0;
    char *command = NULL, *module = NULL;
    char **argv = NULL;
    struct cli_callback_descr *current_module = NULL;

    /* This will allocate memory for command and module */
    parse_command_line(line, &command, &module, &argc, argv);

    dprintf("CLI DEBUG exec: Checking for aliases\n");
    /*
     * Expand shortcuts, if needed
     * This will allocate memory for argc/argv
     */
    expand_aliases(line, &command, &module, &argc, argv);
    
    find_cli_callback_descr(command, current_mode->default_modules,
				&current_module);

    if ((module == NULL) || (current_module->nomodule == true)) {
	dprintf("CLI DEBUG exec : single command detected\n");
	/*
	 * A single word was specified: look at the list of default
	 * commands in the current mode to see if there is a match.
	 * If not, it may be a generic function (exit, help, ...). These
	 * are stored in the list of default commands of the hdt mode.
	 */

	/* First of all it the command doesn't need module, let's rework the arguments */
	if ((current_module->nomodule == true) && ( module != NULL)) {
		dprintf("CLI_DEBUG exec: Reworking arguments with argc=%d\n",argc);
		char **new_argv=NULL;
    		new_argv=malloc((argc + 2)*sizeof(char *));
		for (int argc_iter=0; argc_iter<argc; argc_iter++) {
			dprintf("CLI_DEBUG exec rework : copy %d to %d (%s)\n",argc_iter,argc_iter+1,argv[argc_iter]);
			new_argv[argc_iter+1] = malloc(strlen(argv[argc_iter]));
			strlcpy(new_argv[argc_iter+1], argv[argc_iter], strlen(argv[argc_iter]));
			free(argv[argc_iter]);
		}
		new_argv[0] = malloc(strlen(module)*sizeof(char));
		strlcpy(new_argv[0], module, strlen(module));
		argc++;
		free(argv);
		argv=new_argv;
	}

	if (current_module != NULL)
	    current_module->exec(argc, argv, hardware);
	else if (!strncmp(command, CLI_SHOW, sizeof(CLI_SHOW) - 1) &&
		 current_mode->show_modules != NULL &&
		 current_mode->show_modules->default_callback != NULL)
	    current_mode->show_modules->default_callback(argc, argv, hardware);
	else if (!strncmp(command, CLI_SET, sizeof(CLI_SET) - 1) &&
		 current_mode->set_modules != NULL &&
		 current_mode->set_modules->default_callback != NULL)
	    current_mode->set_modules->default_callback(argc, argv, hardware);
	else {
	    find_cli_callback_descr(command, hdt_mode.default_modules,
				    &current_module);
	    if (current_module != NULL)
		current_module->exec(argc, argv, hardware);
	    else
		more_printf("unknown command: '%s'\n", command);
	}
    } else {
	/*
	 * A module has been specified! We now need to find the type of command.
	 *
	 * The syntax of the cli is the following:
	 *    <type of command> <module on which to operate> <args>
	 * e.g.
	 *    dmi> show system
	 *    dmi> show bank 1
	 *    dmi> show memory 0 1
	 *    pci> show device 12
	 *    hdt> set mode dmi
	 */
	if (!strncmp(command, CLI_SHOW, sizeof(CLI_SHOW) - 1)) {
	    dprintf("CLI DEBUG exec: %s command detected\n", CLI_SHOW);
	    /* Look first for a 'show' callback in the current mode */
	    find_cli_callback_descr(module, current_mode->show_modules,
				    &current_module);
	    /* Execute the callback, if found */
	    if (current_module != NULL)
		current_module->exec(argc, argv, hardware);
	    else {
		dprintf("CLI DEBUG exec: Looking for callback\n");
		/* Look now for a 'show' callback in the hdt mode */
		find_cli_callback_descr(module, hdt_mode.show_modules,
					&current_module);
		/* Execute the callback, if found */
		if (current_module != NULL)
		    current_module->exec(argc, argv, hardware);
		else
		    printf("unknown module: '%s'\n", module);
	    }
	} else if (!strncmp(command, CLI_SET, sizeof(CLI_SET) - 1)) {
	    dprintf("CLI DEBUG exec : %s command detected\n", CLI_SET);
	    /* Look now for a 'set' callback in the hdt mode */
	    find_cli_callback_descr(module, current_mode->set_modules,
				    &current_module);
	    /* Execute the callback, if found */
	    if (current_module != NULL)
		current_module->exec(argc, argv, hardware);
	    else {
		/* Look now for a 'set' callback in the hdt mode */
		find_cli_callback_descr(module, hdt_mode.set_modules,
					&current_module);
		/* Execute the callback, if found */
		if (current_module != NULL)
		    current_module->exec(argc, argv, hardware);
		else
		    printf("unknown module: '%s'\n", module);
	    }
	}
    }

    /* Let's not forget to clean ourselves */
    if (command != NULL)
	free(command);
    if (module != NULL)
	free(module);
    for (i = 0; i < argc; i++)
	free(argv[i]);
    if (argc > 0)
	free(argv);
}

static void reset_prompt(void)
{
    /* No need to display the prompt if we exit */
    if (hdt_cli.mode != EXIT_MODE) {
	printf("%s", hdt_cli.prompt);
	/* Reset the line */
	hdt_cli.cursor_pos = 0;
    }
}

void start_auto_mode(struct s_hardware *hardware)
{
    char *mypch;
    int nb_commands = 0;
    char *commands[MAX_NB_AUTO_COMMANDS];

    more_printf("\nEntering Auto mode\n");

    /* Protecting the auto_label from the strtok modifications */
    char *temp = strdup(hardware->auto_label);

    /* Searching & saving all commands */
    mypch = strtok(temp, AUTO_SEPARATOR);
    while (mypch != NULL) {
	if ((strlen(remove_spaces(mypch)) > 0) &&
	    (remove_spaces(mypch)[0] != AUTO_SEPARATOR[0])) {
	    nb_commands++;
	    if ((commands[nb_commands] = malloc(AUTO_COMMAND_SIZE)) != NULL) {
		sprintf(commands[nb_commands], "%s", remove_spaces(mypch));
	    } else
		nb_commands--;
	}
	mypch = strtok(NULL, AUTO_SEPARATOR);
    }

    free(temp);

    /* Executing found commands */
    for (int i = 1; i <= nb_commands; i++) {
	if (commands[i]) {
	    if (!quiet)
		more_printf("%s%s\n", hdt_cli.prompt, commands[i]);
	    exec_command(commands[i], hardware);
	    free(commands[i]);
	}
    }

    if (!quiet)
	more_printf("\nExiting Auto mode\n");

    more_printf("\n");
}

void print_history(int argc, char **argv, struct s_hardware * hardware)
{
    (void)argc;
    (void)argv;
    (void)hardware;

    reset_more_printf();
    for (int i = 1; i <= MAX_HISTORY_SIZE; i++) {
	if (i == hdt_cli.history_pos) {
	    more_printf("*%d:'%s'\n", i, hdt_cli.history[i]);
	    continue;
	}
	if (strlen(hdt_cli.history[i]) == 0)
	    continue;
	more_printf(" %d:'%s'\n", i, hdt_cli.history[i]);
    }
}

/* Code that manages the cli mode */
void start_cli_mode(struct s_hardware *hardware)
{
    int current_key = 0;
    int future_history_pos = 1;	/* position of the next position in the history */
    int current_future_history_pos = 1;	/* Temp variable */
    bool display_history = true;	/* Temp Variable */
    char temp_command[MAX_LINE_SIZE];

    hdt_cli.cursor_pos = 0;
    memset(hdt_cli.history, 0, sizeof(hdt_cli.history));
    hdt_cli.history_pos = 1;
    hdt_cli.max_history_pos = 1;

    /* Find the mode selected */
    set_mode(HDT_MODE, hardware);
    find_cli_mode_descr(hdt_cli.mode, &current_mode);
    if (current_mode == NULL) {
	/* Shouldn't get here... */
	more_printf("!!! BUG: Mode '%d' unknown.\n", hdt_cli.mode);
	return;
    }

    /* Start the auto mode if the command line is set */
    if (strlen(hardware->auto_label) > 0) {
	start_auto_mode(hardware);
    }

    more_printf("Entering CLI mode\n");

    reset_prompt();

    while (hdt_cli.mode != EXIT_MODE) {

	/* Display the cursor */
	display_cursor(true);

	/* Let's put the cursor blinking until we get an input */
	set_cursor_blink(true);

	/* We wait endlessly for a keyboard input */
	current_key = get_key(stdin, 0);

	/* We have to cancel the blinking mode to prevent
	 * input text to blink */
	set_cursor_blink(false);

	/* Reset autocomplete buffer unless TAB is pressed */
	if (current_key != KEY_TAB)
	    autocomplete_destroy_list();

	switch (current_key) {
	    /* clear until then end of line */
	case KEY_CTRL('k'):
	    /* Clear the end of the line */
	    clear_end_of_line();
	    memset(&INPUT[hdt_cli.cursor_pos], 0,
		   strlen(INPUT) - hdt_cli.cursor_pos);
	    break;

	case KEY_CTRL('c'):
	    printf("\n");
	    reset_prompt();
	    break;

	case KEY_LEFT:
	    if (hdt_cli.cursor_pos > 0) {
		move_cursor_left(1);
		hdt_cli.cursor_pos--;
	    }
	    break;

	case KEY_RIGHT:
	    if (hdt_cli.cursor_pos < (int)strlen(INPUT)) {
		move_cursor_right(1);
		hdt_cli.cursor_pos++;
	    }
	    break;

	case KEY_CTRL('e'):
	case KEY_END:
	    /* Calling with a 0 value will make the cursor move */
	    /* So, let's move the cursor only if needed */
	    if ((strlen(INPUT) - hdt_cli.cursor_pos) > 0) {
		/* Return to the begining of line */
		move_cursor_right(strlen(INPUT) - hdt_cli.cursor_pos);
		hdt_cli.cursor_pos = strlen(INPUT);
	    }
	    break;

	case KEY_CTRL('a'):
	case KEY_HOME:
	    /* Calling with a 0 value will make the cursor move */
	    /* So, let's move the cursor only if needed */
	    if (hdt_cli.cursor_pos > 0) {
		/* Return to the begining of line */
		move_cursor_left(hdt_cli.cursor_pos);
		hdt_cli.cursor_pos = 0;
	    }
	    break;

	case KEY_UP:

	    /* Saving future position */
	    current_future_history_pos = future_history_pos;

	    /* We have to compute the next position */
	    if (future_history_pos == 1) {
		future_history_pos = MAX_HISTORY_SIZE;
	    } else {
		future_history_pos--;
	    }

	    /* Does the next position is valid */
	    if (strlen(hdt_cli.history[future_history_pos]) == 0) {
		/* Position is invalid, restoring position */
		future_history_pos = current_future_history_pos;
		break;
	    }

	    /* Let's make that future position the one we use */
	    memset(INPUT, 0, sizeof(INPUT));
	    strlcpy(INPUT, hdt_cli.history[future_history_pos], sizeof(INPUT));

	    /* Clear the line */
	    clear_line();

	    /* Move to the begining of line */
	    move_cursor_to_column(0);

	    reset_prompt();
	    printf("%s", INPUT);
	    hdt_cli.cursor_pos = strlen(INPUT);
	    break;

	case KEY_DOWN:
	    display_history = true;

	    /* Saving future position */
	    current_future_history_pos = future_history_pos;

	    if (future_history_pos == MAX_HISTORY_SIZE) {
		future_history_pos = 1;
	    } else {
		future_history_pos++;
	    }

	    /* Does the next position is valid */
	    if (strlen(hdt_cli.history[future_history_pos]) == 0)
		display_history = false;

	    /* An exception is made to reach the last empty line */
	    if (future_history_pos == hdt_cli.max_history_pos)
		display_history = true;

	    if (display_history == false) {
		/* Position is invalid, restoring position */
		future_history_pos = current_future_history_pos;
		break;
	    }

	    /* Let's make that future position the one we use */
	    memset(INPUT, 0, sizeof(INPUT));
	    strlcpy(INPUT, hdt_cli.history[future_history_pos], sizeof(INPUT));

	    /* Clear the line */
	    clear_line();

	    /* Move to the begining of line */
	    move_cursor_to_column(0);

	    reset_prompt();
	    printf("%s", INPUT);
	    hdt_cli.cursor_pos = strlen(INPUT);
	    break;

	case KEY_TAB:
	    if (autocomplete_backlog) {
		clear_line();
		/* Move to the begining of line */
		move_cursor_to_column(0);
		reset_prompt();
		printf("%s", autocomplete_last_seen->autocomplete_token);
		strlcpy(INPUT,
			autocomplete_last_seen->autocomplete_token,
			sizeof(INPUT));
		hdt_cli.cursor_pos = strlen(INPUT);

		/* Cycle through the list */
		autocomplete_last_seen = autocomplete_last_seen->next;
		if (autocomplete_last_seen == NULL)
		    autocomplete_last_seen = autocomplete_head;
	    } else {
		printf("\n");
		autocomplete(skip_spaces(INPUT));
		autocomplete_last_seen = autocomplete_head;

		printf("%s%s", hdt_cli.prompt, INPUT);
	    }
	    break;

	case KEY_ENTER:
	    printf("\n");
	    if (strlen(remove_spaces(INPUT)) < 1) {
		reset_prompt();
		break;
	    }
	    exec_command(remove_spaces(INPUT), hardware);
	    hdt_cli.history_pos++;

	    /* Did we reach the end of the history ?*/
	    if (hdt_cli.history_pos > MAX_HISTORY_SIZE) {
		/* Let's return at the beginning */    
		hdt_cli.history_pos = 1;
	    }

	    /* Does the next position is already used ?
	     * If yes, we are cycling in history */
	    if (strlen(INPUT) > 0) {
		/* Let's clean that entry */
		memset(&INPUT,0,sizeof(INPUT));
	    }

	    future_history_pos = hdt_cli.history_pos;
	    if (hdt_cli.history_pos > hdt_cli.max_history_pos)
		hdt_cli.max_history_pos = hdt_cli.history_pos;
	    reset_prompt();
	    break;

	case KEY_CTRL('d'):
	case KEY_DELETE:
	    /* No need to delete when input is empty */
	    if (strlen(INPUT) == 0)
		break;
	    /* Don't delete when cursor is at the end of the line */
	    if (hdt_cli.cursor_pos >= strlen(INPUT))
		break;

	    for (int c = hdt_cli.cursor_pos; c < (int)strlen(INPUT) - 1; c++)
		INPUT[c] = INPUT[c + 1];
	    INPUT[strlen(INPUT) - 1] = '\0';

	    /* Clear the end of the line */
	    clear_end_of_line();

	    /* Print the resulting buffer */
	    printf("%s", INPUT + hdt_cli.cursor_pos);

	    /* Replace the cursor at the proper place */
	    if (strlen(INPUT + hdt_cli.cursor_pos) > 0)
		move_cursor_left(strlen(INPUT + hdt_cli.cursor_pos));
	    break;

	case KEY_DEL:
	case KEY_BACKSPACE:
	    /* Don't delete prompt */
	    if (hdt_cli.cursor_pos == 0)
		break;

	    for (int c = hdt_cli.cursor_pos - 1;
		 c < (int)strlen(INPUT) - 1; c++)
		INPUT[c] = INPUT[c + 1];
	    INPUT[strlen(INPUT) - 1] = '\0';

	    /* Get one char back */
	    move_cursor_left(1);

	    /* Clear the end of the line */
	    clear_end_of_line();

	    /* Print the resulting buffer */
	    printf("%s", INPUT + hdt_cli.cursor_pos - 1);

	    /* Realing to a char before the place we were */
	    hdt_cli.cursor_pos--;
	    move_cursor_to_column(strlen(hdt_cli.prompt) + hdt_cli.cursor_pos +
				  1);

	    break;

	case KEY_F1:
	    printf("\n");
	    exec_command(CLI_HELP, hardware);
	    reset_prompt();
	    break;

	default:
	    if ((current_key < 0x20) || (current_key > 0x7e))
		break;
	    /* Prevent overflow */
	    if (hdt_cli.cursor_pos > MAX_LINE_SIZE - 2)
		break;
	    /* If we aren't at the end of the input line, let's insert */
	    if (hdt_cli.cursor_pos < (int)strlen(INPUT)) {
		char key[2];
		int trailing_chars = strlen(INPUT) - hdt_cli.cursor_pos;
		memset(temp_command, 0, sizeof(temp_command));
		strlcpy(temp_command, INPUT, hdt_cli.cursor_pos);
		sprintf(key, "%c", current_key);
		strncat(temp_command, key, 1);
		strncat(temp_command,
			INPUT + hdt_cli.cursor_pos, trailing_chars);
		memset(INPUT, 0, sizeof(INPUT));
		snprintf(INPUT, sizeof(INPUT), "%s", temp_command);

		/* Clear the end of the line */
		clear_end_of_line();

		/* Print the resulting buffer */
		printf("%s", INPUT + hdt_cli.cursor_pos);

		/* Return where we must put the new char */
		move_cursor_left(trailing_chars);

	    } else {
		putchar(current_key);
		INPUT[hdt_cli.cursor_pos] = current_key;
	    }
	    hdt_cli.cursor_pos++;
	    break;
	}
    }
}
