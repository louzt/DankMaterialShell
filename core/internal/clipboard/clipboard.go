package clipboard

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/proto/ext_data_control"
)

const envServe = "_DMS_CLIPBOARD_SERVE"
const envMime = "_DMS_CLIPBOARD_MIME"
const envPasteOnce = "_DMS_CLIPBOARD_PASTE_ONCE"
const envCacheFile = "_DMS_CLIPBOARD_CACHE"

type Offer struct {
	MimeType string
	Data     []byte
}

// textMimeAliases are offered alongside plain-text content so legacy X11
// clients bridged through XWayland find a target they can convert.
var textMimeAliases = []string{
	"text/plain",
	"text/plain;charset=utf-8",
	"UTF8_STRING",
	"STRING",
	"TEXT",
}

// ExpandOffers turns raw clipboard data into the full offer list to serve,
// adding the standard alias set for text content.
func ExpandOffers(data []byte, mimeType string) []Offer {
	offers := []Offer{{MimeType: mimeType, Data: data}}
	if mimeType != "text/plain" && mimeType != "text/plain;charset=utf-8" {
		return offers
	}
	for _, alias := range textMimeAliases {
		if alias == mimeType {
			continue
		}
		offers = append(offers, Offer{MimeType: alias, Data: data})
	}
	return offers
}

// MaybeServeAndExit intercepts before cobra when re-exec'd as a clipboard
// child. Reads source data into memory, deletes any cache file, then serves.
func MaybeServeAndExit() {
	if os.Getenv(envServe) == "" {
		return
	}

	mimeType := os.Getenv(envMime)
	pasteOnce := os.Getenv(envPasteOnce) == "1"
	cachePath := os.Getenv(envCacheFile)

	var data []byte
	var err error

	switch {
	case cachePath != "":
		data, err = os.ReadFile(cachePath)
		os.Remove(cachePath)
	default:
		data, err = io.ReadAll(os.Stdin)
	}

	if err != nil {
		fmt.Fprintf(os.Stderr, "clipboard: read source: %v\n", err)
		os.Exit(1)
	}

	if err := serveOffers(ExpandOffers(data, mimeType), pasteOnce); err != nil {
		fmt.Fprintf(os.Stderr, "clipboard: serve: %v\n", err)
		os.Exit(1)
	}
	os.Exit(0)
}

func Copy(data []byte, mimeType string) error {
	return copyForkCached(data, mimeType, false)
}

func CopyText(text string) error {
	return Copy([]byte(text), "text/plain;charset=utf-8")
}

func CopyOpts(data []byte, mimeType string, foreground, pasteOnce bool) error {
	if foreground {
		return serveOffers(ExpandOffers(data, mimeType), pasteOnce)
	}
	return copyForkCached(data, mimeType, pasteOnce)
}

func CopyReader(data io.Reader, mimeType string, foreground, pasteOnce bool) error {
	if !foreground {
		return copyFork(data, mimeType, pasteOnce)
	}
	buf, err := io.ReadAll(data)
	if err != nil {
		return fmt.Errorf("read source: %w", err)
	}
	return serveOffers(ExpandOffers(buf, mimeType), pasteOnce)
}

func CopyMulti(offers []Offer, foreground, pasteOnce bool) error {
	if foreground {
		return serveOffers(offers, pasteOnce)
	}
	return copyMultiFork(offers, pasteOnce)
}

func newForkCmd(mimeType string, pasteOnce bool, extra ...string) *exec.Cmd {
	cmd := exec.Command(os.Args[0])
	cmd.Stderr = nil
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	cmd.Env = append(os.Environ(),
		envServe+"=1",
		envMime+"="+mimeType,
	)
	if pasteOnce {
		cmd.Env = append(cmd.Env, envPasteOnce+"=1")
	}
	cmd.Env = append(cmd.Env, extra...)
	return cmd
}

func waitReady(cmd *exec.Cmd) error {
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return fmt.Errorf("stdout pipe: %w", err)
	}
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("start: %w", err)
	}
	var buf [1]byte
	if _, err := stdout.Read(buf[:]); err != nil {
		return fmt.Errorf("waiting for clipboard ready: %w", err)
	}
	return nil
}

func copyForkCached(data []byte, mimeType string, pasteOnce bool) error {
	cacheFile, err := createClipboardCacheFile()
	if err != nil {
		return fmt.Errorf("create cache file: %w", err)
	}
	cachePath := cacheFile.Name()

	if _, err := cacheFile.Write(data); err != nil {
		cacheFile.Close()
		os.Remove(cachePath)
		return fmt.Errorf("write cache file: %w", err)
	}
	if err := cacheFile.Close(); err != nil {
		os.Remove(cachePath)
		return fmt.Errorf("close cache file: %w", err)
	}

	cmd := newForkCmd(mimeType, pasteOnce, envCacheFile+"="+cachePath)
	cmd.Stdin = nil
	if err := waitReady(cmd); err != nil {
		os.Remove(cachePath)
		return err
	}
	return nil
}

func copyFork(data io.Reader, mimeType string, pasteOnce bool) error {
	cmd := newForkCmd(mimeType, pasteOnce)

	if src, ok := data.(*os.File); ok {
		cmd.Stdin = src
		return waitReady(cmd)
	}

	stdin, err := cmd.StdinPipe()
	if err != nil {
		return fmt.Errorf("stdin pipe: %w", err)
	}

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return fmt.Errorf("stdout pipe: %w", err)
	}

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("start: %w", err)
	}
	if _, err := io.Copy(stdin, data); err != nil {
		stdin.Close()
		return fmt.Errorf("write stdin: %w", err)
	}
	if err := stdin.Close(); err != nil {
		return fmt.Errorf("close stdin: %w", err)
	}

	var buf [1]byte
	if _, err := stdout.Read(buf[:]); err != nil {
		return fmt.Errorf("waiting for clipboard ready: %w", err)
	}
	return nil
}

func copyMultiFork(offers []Offer, pasteOnce bool) error {
	args := []string{os.Args[0], "cl", "copy", "--foreground", "--type", "__multi__"}
	if pasteOnce {
		args = append(args, "--paste-once")
	}

	cmd := exec.Command(args[0], args[1:]...)
	cmd.Stdin = nil
	cmd.Stdout = nil
	cmd.Stderr = nil
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}

	stdin, err := cmd.StdinPipe()
	if err != nil {
		return fmt.Errorf("stdin pipe: %w", err)
	}

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("start: %w", err)
	}

	for _, offer := range offers {
		fmt.Fprintf(stdin, "%s\x00%d\x00", offer.MimeType, len(offer.Data))
		if _, err := stdin.Write(offer.Data); err != nil {
			stdin.Close()
			return fmt.Errorf("write offer data: %w", err)
		}
	}
	stdin.Close()

	return nil
}

func signalReady() {
	if os.Getenv(envServe) == "" {
		return
	}
	os.Stdout.Write([]byte{1})
}

func createClipboardCacheFile() (*os.File, error) {
	preferredDirs := []string{}

	if cacheDir, err := os.UserCacheDir(); err == nil {
		preferredDirs = append(preferredDirs, filepath.Join(cacheDir, "dms", "clipboard"))
	}
	preferredDirs = append(preferredDirs, "/var/tmp/dms/clipboard")

	for _, dir := range preferredDirs {
		if err := os.MkdirAll(dir, 0o700); err != nil {
			continue
		}
		cachedData, err := os.CreateTemp(dir, "dms-clipboard-*")
		if err == nil {
			return cachedData, nil
		}
	}
	return os.CreateTemp("", "dms-clipboard-*")
}

// serveOffers owns the Wayland selection until cancelled (or first paste when
// pasteOnce is set), answering every offered mime type with its data.
func serveOffers(offers []Offer, pasteOnce bool) error {
	if len(offers) == 0 {
		return fmt.Errorf("no offers to serve")
	}

	s, err := connectSession()
	if err != nil {
		return err
	}
	defer s.Close()

	dataControlMgr, err := s.requireDataControl()
	if err != nil {
		return err
	}

	device, err := dataControlMgr.GetDataDevice(s.seat)
	if err != nil {
		return fmt.Errorf("get data device: %w", err)
	}
	defer device.Destroy()

	source, err := dataControlMgr.CreateDataSource()
	if err != nil {
		return fmt.Errorf("create data source: %w", err)
	}

	offerData := make(map[string][]byte, len(offers))
	for _, offer := range offers {
		if err := source.Offer(offer.MimeType); err != nil {
			return fmt.Errorf("offer %s: %w", offer.MimeType, err)
		}
		offerData[offer.MimeType] = offer.Data
	}

	cancelled := make(chan struct{})
	pasted := make(chan struct{}, 1)

	source.SetSendHandler(func(e ext_data_control.ExtDataControlSourceV1SendEvent) {
		_ = syscall.SetNonblock(e.Fd, false)
		file := os.NewFile(uintptr(e.Fd), "pipe")
		defer file.Close()

		if data, ok := offerData[e.MimeType]; ok {
			_, _ = file.Write(data)
		}

		select {
		case pasted <- struct{}{}:
		default:
		}
	})

	source.SetCancelledHandler(func(e ext_data_control.ExtDataControlSourceV1CancelledEvent) {
		close(cancelled)
	})

	if err := device.SetSelection(source); err != nil {
		return fmt.Errorf("set selection: %w", err)
	}

	s.display.Roundtrip()
	signalReady()

	for {
		select {
		case <-cancelled:
			return nil
		case <-pasted:
			if pasteOnce {
				return nil
			}
		default:
			if err := s.ctx.Dispatch(); err != nil {
				return nil
			}
		}
	}
}

func Paste() ([]byte, string, error) {
	s, err := connectSession()
	if err != nil {
		return nil, "", err
	}
	defer s.Close()

	dataControlMgr, err := s.requireDataControl()
	if err != nil {
		return nil, "", err
	}

	device, err := dataControlMgr.GetDataDevice(s.seat)
	if err != nil {
		return nil, "", fmt.Errorf("get data device: %w", err)
	}
	defer device.Destroy()

	offerMimeTypes := make(map[*ext_data_control.ExtDataControlOfferV1][]string)

	device.SetDataOfferHandler(func(e ext_data_control.ExtDataControlDeviceV1DataOfferEvent) {
		if e.Id == nil {
			return
		}
		offerMimeTypes[e.Id] = nil
		e.Id.SetOfferHandler(func(me ext_data_control.ExtDataControlOfferV1OfferEvent) {
			offerMimeTypes[e.Id] = append(offerMimeTypes[e.Id], me.MimeType)
		})
	})

	var selectionOffer *ext_data_control.ExtDataControlOfferV1
	gotSelection := false

	device.SetSelectionHandler(func(e ext_data_control.ExtDataControlDeviceV1SelectionEvent) {
		selectionOffer = e.Id
		gotSelection = true
	})

	s.display.Roundtrip()
	s.display.Roundtrip()

	if !gotSelection || selectionOffer == nil {
		return nil, "", fmt.Errorf("no clipboard data")
	}

	selectedMime := selectPreferredMimeType(offerMimeTypes[selectionOffer])
	if selectedMime == "" {
		return nil, "", fmt.Errorf("no supported mime type")
	}

	r, w, err := os.Pipe()
	if err != nil {
		return nil, "", fmt.Errorf("create pipe: %w", err)
	}
	defer r.Close()

	if err := selectionOffer.Receive(selectedMime, int(w.Fd())); err != nil {
		w.Close()
		return nil, "", fmt.Errorf("receive: %w", err)
	}
	w.Close()

	s.display.Roundtrip()

	data, err := io.ReadAll(r)
	if err != nil {
		return nil, "", fmt.Errorf("read: %w", err)
	}

	return data, selectedMime, nil
}

func PasteText() (string, error) {
	data, _, err := Paste()
	if err != nil {
		return "", err
	}
	return string(data), nil
}

func selectPreferredMimeType(mimes []string) string {
	preferred := []string{
		"text/plain;charset=utf-8",
		"text/plain",
		"UTF8_STRING",
		"STRING",
		"TEXT",
		"image/png",
		"image/jpeg",
	}

	for _, pref := range preferred {
		for _, mime := range mimes {
			if mime == pref {
				return mime
			}
		}
	}

	if len(mimes) > 0 {
		return mimes[0]
	}
	return ""
}

func IsImageMimeType(mime string) bool {
	return len(mime) > 6 && mime[:6] == "image/"
}
