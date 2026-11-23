// Package main is the C bridge of MediaTok's VLESS core: a thin wrapper around xray-core that
// starts one instance from a JSON config. Built as a c-archive and linked into the dynamic
// framework MTXrayCore by ../build-core.sh; the app opens that framework with dlopen only when
// the user switches the VPN on, so this runtime does not start otherwise.
//
// The exported functions are the whole ABI (MTXrayCore.swift resolves them with dlsym):
//
//	char *mtxc_version(void);            caller frees with mtxc_free
//	char *mtxc_last_error(void);         caller frees with mtxc_free; "" after a success
//	void  mtxc_free(char *);
//	int   mtxc_test(const char *json);   0 = the config is valid
//	int   mtxc_start(const char *json);  0 = running
//	int   mtxc_stop(void);               0 = stopped, 5 = nothing was running
//	int   mtxc_is_running(void);
//	long long mtxc_uplink(void);         bytes through the "proxy" outbound since start
//	long long mtxc_downlink(void);
//
// Result codes: 0 ok, 1 already running, 2 invalid argument, 3 config invalid, 4 start failed,
// 5 not running, 6 recovered panic. Start and stop are serialised by a mutex and block until the
// core is up or down (no network I/O happens during start).
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"bytes"
	"fmt"
	"sync"
	"unsafe"

	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/features/stats"
	"github.com/xtls/xray-core/infra/conf/serial"

	// What MTXrayConfig.swift can produce: a SOCKS5 inbound, a VLESS outbound over tcp / ws / grpc /
	// httpupgrade / xhttp with tls or reality, a freedom outbound, stats and policy. The JSON loader
	// (infra/conf) already pulls these packages in; importing them here keeps their registrations
	// explicit. main/distro/all is not used: it adds the command-line tools and the TOML / YAML /
	// remote config loaders, which the app never needs.
	_ "github.com/xtls/xray-core/app/dispatcher"
	_ "github.com/xtls/xray-core/app/log"
	_ "github.com/xtls/xray-core/app/policy"
	_ "github.com/xtls/xray-core/app/proxyman/inbound"
	_ "github.com/xtls/xray-core/app/proxyman/outbound"
	_ "github.com/xtls/xray-core/app/stats"
	_ "github.com/xtls/xray-core/proxy/freedom"
	_ "github.com/xtls/xray-core/proxy/socks"
	_ "github.com/xtls/xray-core/proxy/vless/outbound"
	_ "github.com/xtls/xray-core/transport/internet/grpc"
	_ "github.com/xtls/xray-core/transport/internet/headers/http"
	_ "github.com/xtls/xray-core/transport/internet/headers/noop"
	_ "github.com/xtls/xray-core/transport/internet/httpupgrade"
	_ "github.com/xtls/xray-core/transport/internet/reality"
	_ "github.com/xtls/xray-core/transport/internet/splithttp"
	_ "github.com/xtls/xray-core/transport/internet/tagged/taggedimpl"
	_ "github.com/xtls/xray-core/transport/internet/tcp"
	_ "github.com/xtls/xray-core/transport/internet/tls"
	_ "github.com/xtls/xray-core/transport/internet/websocket"
)

const (
	resultOK              = 0
	resultAlreadyRunning  = 1
	resultInvalidArgument = 2
	resultConfigInvalid   = 3
	resultStartFailed     = 4
	resultNotRunning      = 5
	resultPanic           = 6

	outboundTag = "proxy"
)

var (
	mutex     sync.Mutex
	instance  *core.Instance
	errorText string
)

func setError(text string) {
	errorText = text
}

func loadConfig(json *C.char) (*core.Config, int) {
	if json == nil {
		setError("empty config")
		return nil, resultInvalidArgument
	}
	raw := C.GoString(json)
	if len(raw) == 0 {
		setError("empty config")
		return nil, resultInvalidArgument
	}
	config, err := serial.LoadJSONConfig(bytes.NewReader([]byte(raw)))
	if err != nil {
		setError(err.Error())
		return nil, resultConfigInvalid
	}
	return config, resultOK
}

//export mtxc_version
func mtxc_version() *C.char {
	return C.CString(core.Version())
}

//export mtxc_free
func mtxc_free(pointer *C.char) {
	if pointer != nil {
		C.free(unsafe.Pointer(pointer))
	}
}

//export mtxc_last_error
func mtxc_last_error() *C.char {
	mutex.Lock()
	defer mutex.Unlock()
	return C.CString(errorText)
}

//export mtxc_test
func mtxc_test(json *C.char) (result C.int) {
	mutex.Lock()
	defer mutex.Unlock()
	defer func() {
		if recovered := recover(); recovered != nil {
			setError(fmt.Sprint(recovered))
			result = resultPanic
		}
	}()
	setError("")
	_, code := loadConfig(json)
	return C.int(code)
}

//export mtxc_start
func mtxc_start(json *C.char) (result C.int) {
	mutex.Lock()
	defer mutex.Unlock()
	defer func() {
		if recovered := recover(); recovered != nil {
			setError(fmt.Sprint(recovered))
			if instance != nil {
				_ = instance.Close()
				instance = nil
			}
			result = resultPanic
		}
	}()
	if instance != nil {
		setError("already running")
		return resultAlreadyRunning
	}
	setError("")
	config, code := loadConfig(json)
	if code != resultOK {
		return C.int(code)
	}
	server, err := core.New(config)
	if err != nil {
		setError(err.Error())
		return resultStartFailed
	}
	if err := server.Start(); err != nil {
		_ = server.Close()
		setError(err.Error())
		return resultStartFailed
	}
	instance = server
	return resultOK
}

//export mtxc_stop
func mtxc_stop() (result C.int) {
	mutex.Lock()
	defer mutex.Unlock()
	defer func() {
		if recovered := recover(); recovered != nil {
			setError(fmt.Sprint(recovered))
			instance = nil
			result = resultPanic
		}
	}()
	if instance == nil {
		return resultNotRunning
	}
	err := instance.Close()
	instance = nil
	if err != nil {
		setError(err.Error())
	} else {
		setError("")
	}
	return resultOK
}

//export mtxc_is_running
func mtxc_is_running() C.int {
	mutex.Lock()
	defer mutex.Unlock()
	if instance != nil {
		return 1
	}
	return 0
}

func counter(direction string) C.longlong {
	mutex.Lock()
	defer mutex.Unlock()
	if instance == nil {
		return 0
	}
	manager, ok := instance.GetFeature(stats.ManagerType()).(stats.Manager)
	if !ok || manager == nil {
		return 0
	}
	value := manager.GetCounter("outbound>>>" + outboundTag + ">>>traffic>>>" + direction)
	if value == nil {
		return 0
	}
	return C.longlong(value.Value())
}

//export mtxc_uplink
func mtxc_uplink() C.longlong {
	return counter("uplink")
}

//export mtxc_downlink
func mtxc_downlink() C.longlong {
	return counter("downlink")
}

func main() {}
