package main

import (
	"net/http"
	"path"
	"regexp"
	"sort"
	"strings"
	"sync"
)

type Router interface {
	HandleFunc(pattern string, f func(w http.ResponseWriter, r *http.Request))
	HandleRegexFunc(pattern string, f func(w http.ResponseWriter, r *http.Request), weight ...int)
	ServeHTTP(w http.ResponseWriter, r *http.Request)
}


func NewRouter() Router {
	return &routes{
		routes: make(map[string]*routeInfo),
		regexRoutes: make([]*routeInfo, 0, 10),
	}
}

type routeInfo struct {
	path    string
	regex   *regexp.Regexp
	handler http.HandlerFunc
	weight  int
}

type routes struct {
	mux         sync.RWMutex
	routes      map[string]*routeInfo
	regexRoutes []*routeInfo
}

func (route *routes) HandleFunc(pattern string, f func(w http.ResponseWriter, r *http.Request)) {
	route.mux.Lock()
	defer route.mux.Unlock()
	route.routes[pattern] = &routeInfo{
		path:    pattern,
		handler: f,
	}
}

func (route *routes) HandleRegexFunc(pattern string, f func(w http.ResponseWriter, r *http.Request), weight ...int) {
	weight = append(weight, 100)
	route.mux.Lock()
	defer route.mux.Unlock()
	route.regexRoutes = append(route.regexRoutes, &routeInfo{
		regex:   regexp.MustCompile(pattern),
		handler: f,
		path:    pattern,
		weight:  weight[0],
	})
	sort.Slice(route.regexRoutes, func(i, j int) bool {
		return route.regexRoutes[i].weight > route.regexRoutes[j].weight
	})
}

func (route *routes) cleanPath(p string) string {
	if p == "" {
		return "/"
	}
	if p[0] != '/' {
		p = "/" + p
	}

	np := path.Clean(p)

	// path.Clean removes trailing slash except for root;
	// put the trailing slash back if necessary.
	if p[len(p)-1] == '/' && np != "/" {
		// Fast path for common case of p being the string we want:
		if len(p) == len(np)+1 && strings.HasPrefix(p, np) {
			np = p
		} else {
			np += "/"
		}
	}
	return np
}

func (route *routes) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	rPath := route.cleanPath(r.URL.Path)
	if handle, ok := route.routes[rPath]; ok {
		handle.handler(w, r)
		return
	}

	for _, handle := range route.regexRoutes {
		if handle.regex.MatchString(rPath) {
			handle.handler(w, r)
			return
		}
	}

	http.NotFound(w, r)
}