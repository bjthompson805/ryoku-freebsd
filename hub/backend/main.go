// ryoku-hub is the Go backend for the Ryoku Settings GUI. The Quickshell front end
// (qs -c hub) shells out to it the same way the rest of the desktop talks to
// ryoku-shell: a subcommand prints data on stdout or mutates persisted state.
package main

import (
	"encoding/json"
	"fmt"
	"os"
)

var commands = map[string]func([]string) error{
	"keybinds": runKeybinds,
	"config":   runConfig,
	"hypr":     runHypr,
	"extras":   runExtras,
	"lock":     runLock,
	"rice":     runRice,
}

func main() {
	if len(os.Args) < 2 || commands[os.Args[1]] == nil {
		usage()
		os.Exit(2)
	}
	if err := commands[os.Args[1]](os.Args[2:]); err != nil {
		fmt.Fprintln(os.Stderr, "ryoku-hub:", err)
		os.Exit(1)
	}
}

func runKeybinds([]string) error {
	b, err := json.Marshal(keybinds())
	if err != nil {
		return err
	}
	fmt.Println(string(b))
	return nil
}

func runConfig(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("config needs get|set")
	}
	switch args[0] {
	case "get":
		if len(args) < 2 {
			return fmt.Errorf("config get needs a key")
		}
		v, ok := configGet(args[1])
		if !ok {
			return fmt.Errorf("unknown config key: %s", args[1])
		}
		fmt.Println(v)
		return nil
	case "set":
		if len(args) < 3 {
			return fmt.Errorf("config set needs a key and value")
		}
		return configSet(args[1], args[2])
	default:
		return fmt.Errorf("config needs get|set")
	}
}

func usage() {
	fmt.Fprint(os.Stderr, `usage:
  ryoku-hub keybinds
  ryoku-hub config get <key>
  ryoku-hub config set <key> <value>
  ryoku-hub hypr get|defaults|cursors|layouts
  ryoku-hub hypr variants <layout>
  ryoku-hub hypr save|preview <json>
  ryoku-hub hypr restore
  ryoku-hub extras plugincatalog|plugin <id>|pluginremove <id>
  ryoku-hub lock list
  ryoku-hub lock set <slug>
  ryoku-hub rice list|capture|apply|restore|save|fork|delete|files|export|catalog|install|publish
`)
}
