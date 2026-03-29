package main

import (
	"fmt"
	"os"

	"xworkmate/go_core/internal/acp"
	"xworkmate/go_core/internal/toolbridge"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "serve" {
		if err := acp.Serve(os.Args[2:]); err != nil {
			fmt.Fprintf(os.Stderr, "%v\n", err)
			os.Exit(1)
		}
		return
	}

	toolbridge.Run(os.Stdin, os.Stdout)
}
