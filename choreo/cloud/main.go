package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"cloud.local/docs"
	httpSwagger "github.com/swaggo/http-swagger/v2"
)

var (
	storage sync.Map
)

func HealthHandler(w http.ResponseWriter, r *http.Request) {
	raw, _ := json.Marshal(map[string]interface{}{
		"message":     "Serveless service is healthy",
		"environment": GetConfig().Env,
		"timestamp":   time.Now(),
	})
	_, _ = w.Write(raw)
}

// @Summary	curent api index
// @Tags		cloud
// @Router		/ [get]
// @Success	200	{string}	map[string]interface{}	"successful operation"
// @Failure	400	{object}	ErrorResponse			"bad request"
// @Failure	400	{string}	string					"error bad request"
// @Failure	500	{object}	ErrorResponse			"server error request"
func IndexHandler(w http.ResponseWriter, r *http.Request) {
	io.WriteString(w, "hello world")
}

// @Summary	Get first
// @Tags		cloud
// @Param		id	path	string	true	"execute"
// @Router		/api/{id} [get]
// @Success	202	{string}	map[string]interface{}	"successful operation"
// @Success	200	{string}	map[string]interface{}	"successful operation"
// @Failure	400	{object}	ErrorResponse			"bad request"
// @Failure	500	{object}	ErrorResponse			"server error request"
func GetHandler(w http.ResponseWriter, r *http.Request) {
	var data = make(map[string]interface{})
	storage.Range(func(key, value interface{}) bool {
		data[key.(string)] = value
		return true
	})

	raw, _ := json.Marshal(data)
	_, _ = w.Write(raw)
}

// @Summary	Post first
// @Tags		cloud
// @Param		id	path	string	true	"execute"
// @Router		/api/{id} [post]
// @Success	202	{string}	map[string]interface{}	"successful operation"
// @Success	200	{string}	map[string]interface{}	"successful operation"
// @Failure	400	{object}	ErrorResponse			"bad request"
// @Failure	500	{object}	ErrorResponse			"server error request"
func PostHandler(w http.ResponseWriter, r *http.Request) {
	var value interface{}
	d := json.NewDecoder(r.Body)
	err := d.Decode(&value)
	if err != nil {
		http.Error(w, fmt.Sprintf(`{"error":"%v"}`, err), 200)
		return
	}

	key := r.URL.Query().Get("key")
	storage.LoadOrStore(key, value)
	w.Header().Add("Content-Type", "application/json; charset=utf-8")
	io.WriteString(w, fmt.Sprintf(`{"key":"%v", "value":"%v"}`, key, value))
}

// @Summary	Put first
// @Tags		cloud
// @Param		id	path	string	true	"execute"
// @Router		/api/{id} [put]
// @Success	202	{string}	map[string]interface{}	"successful operation"
// @Success	200	{string}	map[string]interface{}	"successful operation"
// @Failure	400	{object}	ErrorResponse			"bad request"
// @Failure	500	{object}	ErrorResponse			"server error request"
func PutHandler(w http.ResponseWriter, r *http.Request) {}

// @Summary	Delete first
// @Tags		cloud
// @Param		id	path	string	true	"execute"
// @Router		/api/{id} [delete]
// @Success	202	{string}	map[string]interface{}	"successful operation"
// @Success	200	{string}	map[string]interface{}	"successful operation"
// @Failure	400	{object}	ErrorResponse			"bad request"
// @Failure	500	{object}	ErrorResponse			"server error request"
func DeleteHandler(w http.ResponseWriter, r *http.Request) {}

// @Summary	Options first
// @Tags		cloud
// @Param		id	path	string	true	"execute"
// @Router		/api/{id} [options]
// @Success	202	{string}	map[string]interface{}	"successful operation"
// @Success	200	{string}	map[string]interface{}	"successful operation"
// @Failure	400	{object}	ErrorResponse			"bad request"
// @Failure	500	{object}	ErrorResponse			"server error request"
func OptionsHandler(w http.ResponseWriter, r *http.Request) {}

// @Summary	Get second
// @Tags		cloud
// @Param		id	path	string	true	"execute"
// @Param		sub	path	string	true	"execute"
// @Router		/api/{id}/{sub} [get]
// @Success	202	{string}	map[string]interface{}	"successful operation"
// @Success	200	{string}	map[string]interface{}	"successful operation"
// @Failure	400	{object}	ErrorResponse			"bad request"
// @Failure	500	{object}	ErrorResponse			"server error request"
func Get2Handler(w http.ResponseWriter, r *http.Request) {}

// @Summary	Start push stream
// @Tags		cloud
// @Param		id	path	string	true	"execute"
// @Param		sub	path	string	true	"execute"
// @Router		/api/{id}/{sub} [post]
// @Success	202	{string}	map[string]interface{}	"successful operation"
// @Success	200	{string}	map[string]interface{}	"successful operation"
// @Failure	400	{object}	ErrorResponse			"bad request"
// @Failure	500	{object}	ErrorResponse			"server error request"
func Post2Handler(w http.ResponseWriter, r *http.Request) {}

// @Summary	Put second
// @Tags		cloud
// @Param		id	path	string	true	"execute"
// @Param		sub	path	string	true	"execute"
// @Router		/api/{id}/{sub} [put]
// @Success	202	{string}	map[string]interface{}	"successful operation"
// @Success	200	{string}	map[string]interface{}	"successful operation"
// @Failure	400	{object}	ErrorResponse			"bad request"
// @Failure	500	{object}	ErrorResponse			"server error request"
func Put2Handler(w http.ResponseWriter, r *http.Request) {}

// @Summary	Delete second
// @Tags		cloud
// @Param		id	path	string	true	"execute"
// @Param		sub	path	string	true	"execute"
// @Router		/api/{id}/{sub} [delete]
// @Success	202	{string}	map[string]interface{}	"successful operation"
// @Success	200	{string}	map[string]interface{}	"successful operation"
// @Failure	400	{object}	ErrorResponse			"bad request"
// @Failure	500	{object}	ErrorResponse			"server error request"
func Delete2Handler(w http.ResponseWriter, r *http.Request) {}

// @Summary	Options second
// @Tags		cloud
// @Param		id	path	string	true	"execute"
// @Param		sub	path	string	true	"execute"
// @Router		/api/{id}/{sub} [options]
// @Success	202	{string}	map[string]interface{}	"successful operation"
// @Success	200	{string}	map[string]interface{}	"successful operation"
// @Failure	400	{object}	ErrorResponse			"bad request"
// @Failure	500	{object}	ErrorResponse			"server error request"
func Options2Handler(w http.ResponseWriter, r *http.Request) {}

type ErrorResponse struct {
	Message string `json:"error" example:"error message"`
}

func run() {
	ctx := context.Background()
again:
	storage.Store("time", time.Now().Format("2006-01-02T15:04:05Z"))
	shell := exec.CommandContext(ctx, "sh", "-c", "/app/cloudflare server")
	shell.Stdout = os.Stdout
	shell.Stderr = os.Stdout
	err := shell.Run()
	if ctx.Err() == nil {
		log.Printf("exec exit %v, start again .... \n", err)
		time.Sleep(10 * time.Second)
		goto again
	}
	if err != nil {
		log.Printf("exec exit %v, exit ....", err)
	}

	goto again
}

// cloud service
//
//	@title			cloud
//	@version		v
//	@description	cloud service
//	@host			localhost:8080
//	@BasePath		/
func main() {
	handler := NewRouter()
	cfg := GetConfig()

	storage.Store("time", time.Now().Format("2006-01-02T15:04:05Z"))

	docs.SwaggerInfo.Host = fmt.Sprintf("%s:%d", cfg.Hostname, cfg.Port)
	u := fmt.Sprintf("http://%v:%d/swagger/doc.json", cfg.Hostname, cfg.Port)
	handler.HandleRegexFunc("/swagger/.*", httpSwagger.Handler(
		httpSwagger.URL(u), //The url pointing to API definition
		httpSwagger.DeepLinking(true),
		httpSwagger.DocExpansion("none"),
		httpSwagger.DomID("swagger-ui"),
	), 1000)
	handler.HandleFunc("/healthz", HealthHandler)
	handler.HandleFunc("/", IndexHandler)
	handler.HandleFunc("/api/get", GetHandler)
	handler.HandleFunc("/api/post", PostHandler)

	app := http.Server{
		Handler: handler,
		Addr:    ":" + fmt.Sprintf("%d", cfg.Port),
	}

	go run()
	go func() {
		log.Printf("port=%d serverless service is starting...", cfg.Port)
		if err := app.ListenAndServe(); err != nil {
			log.Printf("failed to start server: %v", err)
		}
	}()

	sigtermC := make(chan os.Signal, 1)
	signal.Notify(sigtermC, os.Interrupt, syscall.SIGTERM, syscall.SIGABRT, syscall.SIGKILL)

	<-sigtermC // block until SIGTERM is received
	log.Printf("SIGTERM received: gracefully shutting down...")

	if err := app.Shutdown(context.Background()); err != nil {
		log.Printf("server shutdown error: %v", err)
	}
}
