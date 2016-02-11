#
# Makefile for Docker data volume VMDK plugin  
#
# Builds client-side (docker engine) volume plug in code, and ESX-side VIB
#
# Expectations:
#   By default, needs docker (for containerized go build)
#   Can be used without docker, but:
#		- the final VIB assembly needs docker and will be skipped
#		- requires golang 1.5+ installed
#		- requires libc-i386-dev package for 32-bit build installed
# 

# Place binaries here
BIN := ./bin

# source locations for Make
ESX_SRC     := vmdkops-esxsrv # esx service for docker volume ops

#  binaries location
PNAME  := docker-vmdk-plugin
PLUGIN_BIN = $(BIN)/$(PNAME)

VIBFILE := vmware-esx-vmdkops-1.0.0.vib
VIB_BIN := $(BIN)/$(VIBFILE) 

# plugin name, for go build
PLUGIN := github.com/vmware/$(PNAME)

# container name 
CNAME := $(PNAME)-go-bld

ifeq ($(DOCKER_USE), false)
	GO := GO15VENDOREXPERIMENT=1 go
	DOCKER := echo *** Skipping "(DOCKER_USE=false):" docker
else
	DOCKER := docker
	#  in the container GOPATH=/go
	GO := docker run --rm -w /go/src/$(PLUGIN)  -v $(PWD):/go/src/$(PLUGIN) $(CNAME) go
endif
export DOCKER_USE

# make sure we rebuild of vmkdops or Dockerfile change (since we develop them together)
EXTRA_SRC = vmdkops/*.go 

# All sources. We rebuild if anything changes here
SRC = plugin.go main.go 

#  Targets 
#
.PHONY: build
build: prereqs .build_container $(PLUGIN_BIN)
	@cd  $(ESX_SRC)  ; $(MAKE)  $@ 

.PHONY: prereqs
prereqs:
	@./check.sh

$(PLUGIN_BIN): $(SRC) $(EXTRA_SRC) Dockerfile
	@-mkdir -p $(BIN)
	@echo "Building $(PLUGIN_BIN) ..." 
	$(GO) build -o $(PLUGIN_BIN) $(PLUGIN)


.build_container: Dockerfile
	$(DOCKER) build -t $(CNAME) .
	@touch $@
	 

.PHONY: clean
clean: 
	rm -f $(BIN)/* .build_*
	@cd  $(ESX_SRC)  ; $(MAKE)  $@

	
#TBD: this is a good place to add unit tests...	
.PHONY: test
test: build
	$(GO) test $(PLUGIN)/vmdkops $(PLUGIN)
	@echo "*** Info: No tests in plugin folder yet"
	@cd  $(ESX_SRC)  ; $(MAKE)  $@
	
#
# 'make deploy'
# ----------
# temporary goal to simplify my deployments and sanity check test (create/delete)
#
# expectations: 
#   Need target machines (ESX/Guest) to have proper ~/.ssh/authorized_keys


# msterin's ESX host and ubuntu guest current IPs
HOST  := root@10.20.104.35
GUEST := root@10.20.105.74

# bin locations on target guest
GLOC := /usr/local/bin


# vib install: we install by file name but remove by internal name
VIBNAME := vmware-esx-vmdkops-service
VIBCMD  := localcli software vib


.PHONY: deploy
# ignore failures in copy to guest (can be busy) and remove vib (can be not installed)
deploy: build
	./build.sh
	-scp $(PLUGIN_BIN) $(GUEST):$(GLOC)/
	scp $(VIB_BIN) $(HOST):/tmp
	-ssh $(HOST) $(VIBCMD) remove --vibname $(VIBNAME)
	ssh  $(HOST) $(VIBCMD) install --no-sig-check  -v /tmp/$(VIBFILE)

.PHONY: cleanremote
cleanremote:
	-ssh $(GUEST) rm $(GLOC)/$(DVOLPLUG)
	-ssh $(HOST) $(VIBCMD) remove --vibname $(VIBNAME)

# "make simpletest" assumes all services are started manually, and simply 
# does sanity check of create/remove docker volume on the guest
TEST_VOL_NAME := MyVolume

.PHONY: testremote
testremote:  
	rsh $(GUEST)  docker volume create \
			--driver=vmdk --name=$(TEST_VOL_NAME) \
			-o size=1gb -o policy=good
	rsh $(GUEST)  docker volume ls
	rsh $(GUEST)  docker volume inspect $(TEST_VOL_NAME)
	rsh $(GUEST)  docker volume rm $(TEST_VOL_NAME)
	