package main

import (
	"fmt"
	"strings"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/log"
	sharedpam "github.com/AvengeMedia/DankMaterialShell/core/internal/pam"
	"github.com/spf13/cobra"
)

var authCmd = &cobra.Command{
	Use:   "auth",
	Short: "Manage DMS authentication sync",
	Long:  "Manage shared PAM/authentication setup for DMS greeter and lock screen",
}

var authSyncCmd = &cobra.Command{
	Use:     "sync",
	Short:   "Sync DMS authentication configuration",
	Long:    "Apply shared PAM/authentication changes for the lock screen and greeter based on current DMS settings",
	PreRunE: preRunPrivileged,
	Run: func(cmd *cobra.Command, args []string) {
		yes, _ := cmd.Flags().GetBool("yes")
		term, _ := cmd.Flags().GetBool("terminal")
		if term {
			if err := syncAuthInTerminal(yes); err != nil {
				log.Fatalf("Error launching auth sync in terminal: %v", err)
			}
			return
		}
		if err := syncAuth(yes); err != nil {
			log.Fatalf("Error syncing authentication: %v", err)
		}
	},
}

var authResolveLockCmd = &cobra.Command{
	Use:   "resolve-lock",
	Short: "Generate the lock-screen PAM config from the system auth stack",
	Long: "Resolve the distribution's PAM auth stack into a self-contained lock-screen config under the user state directory.\n" +
		"Runs unprivileged (reads /etc/pam.d, writes to the user's state dir) and is used by the shell as a fallback when /etc/pam.d/dankshell is not managed.\n" +
		"Prints the path of the generated file.",
	Run: func(cmd *cobra.Command, args []string) {
		quiet, _ := cmd.Flags().GetBool("quiet")
		logFunc := func(msg string) {
			if !quiet {
				fmt.Println(msg)
			}
		}
		path, err := sharedpam.WriteUserLockscreenPamConfig(logFunc)
		if err != nil {
			log.Fatalf("Error resolving lock-screen PAM config: %v", err)
		}
		fmt.Println(path)
	},
}

func init() {
	authSyncCmd.Flags().BoolP("yes", "y", false, "Non-interactive mode: skip prompts")
	authSyncCmd.Flags().BoolP("terminal", "t", false, "Run auth sync in a new terminal (for entering sudo password)")
	authResolveLockCmd.Flags().BoolP("quiet", "q", false, "Only print the resulting file path")
}

func syncAuth(nonInteractive bool) error {
	if !nonInteractive {
		fmt.Println("=== DMS Authentication Sync ===")
		fmt.Println()
	}

	logFunc := func(msg string) {
		fmt.Println(msg)
	}

	if err := sharedpam.SyncAuthConfig(logFunc, "", sharedpam.SyncAuthOptions{}); err != nil {
		return err
	}

	if !nonInteractive {
		fmt.Println("\n=== Authentication Sync Complete ===")
		fmt.Println("\nAuthentication changes have been applied.")
	}

	return nil
}

func syncAuthInTerminal(nonInteractive bool) error {
	syncFlags := make([]string, 0, 1)
	if nonInteractive {
		syncFlags = append(syncFlags, "--yes")
	}

	shellSyncCmd := "dms auth sync"
	if len(syncFlags) > 0 {
		shellSyncCmd += " " + strings.Join(syncFlags, " ")
	}
	shellCmd := shellSyncCmd + `; echo; echo "Authentication sync finished. Closing in 3 seconds..."; sleep 3`
	return runCommandInTerminal(shellCmd)
}
