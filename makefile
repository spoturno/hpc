# CXX = /opt/homebrew/opt/llvm/bin/clang++
# CXXFLAGS = -std=c++17 -Wall -pipe $(EXTRACXXFLAGS) -I/usr/local/opt/llvm/include -fopenmp
# LDFLAGS = -pthread $(CXXFLAGS) $(EXTRALDFLAGS) -L/usr/local/opt/llvm/lib -Wl,-rpath,/usr/local/opt/llvm/lib -lomp

CXX = clang++
MPICXX = mpic++
CXXFLAGS = -std=c++17 -Wall -pipe $(EXTRACXXFLAGS) -I/opt/homebrew/opt/libomp/include -Xclang -fopenmp
MPICXXFLAGS = -std=c++17 -Wall -pipe $(EXTRACXXFLAGS)

LDFLAGS = -pthread $(CXXFLAGS) $(EXTRALDFLAGS) -L/opt/homebrew/opt/libomp/lib -lomp
MPILDFLAGS = -pthread $(MPICXXFLAGS) $(EXTRALDFLAGS)

OBJS = main.o old-search.o evaluation.o
TEST_OBJS = timing-tests.o old-search.o evaluation.o
MPI_OBJS = main-mpi.o search-mpi.o evaluation-mpi.o
RS_OBJS = main.o search-rs.o evaluation.o
SHT_OBJS = main.o search-sht.o evaluation.o

BINDIR = /usr/local/bin

EXE = engine
TEST_EXE = timing-tests
MPI_EXE = engine-mpi
RS_EXE = engine-rs
SHT_EXE = engine-sht

ifeq ($(BUILD),debug)
	CXXFLAGS += -O0 -g -fno-omit-frame-pointer
else
	CXXFLAGS += -O3 -DNDEBUG
endif

all: $(EXE) $(TEST_EXE) $(MPI_EXE) $(RS_EXE) $(SHT_EXE)

$(EXE): $(OBJS)
	$(CXX) -o $@ $(OBJS) $(LDFLAGS)

$(TEST_EXE): $(TEST_OBJS)
	$(CXX) -o $@ $(TEST_OBJS) $(LDFLAGS)

$(MPI_EXE): $(MPI_OBJS)
	$(MPICXX) -o $@ $(MPI_OBJS) $(MPILDFLAGS)

$(RS_EXE): $(RS_OBJS)
	$(CXX) -o $@ $(RS_OBJS) $(LDFLAGS)

$(SHT_EXE): $(SHT_OBJS)
	$(CXX) -o $@ $(SHT_OBJS) $(LDFLAGS)

# MPI object file rules
main-mpi.o: main.cpp
	$(MPICXX) $(MPICXXFLAGS) -DUSE_MPI_SEARCH -c -o $@ $<

search-mpi.o: search-mpi.cpp
	$(MPICXX) $(MPICXXFLAGS) -c -o $@ $<

evaluation-mpi.o: evaluation.cpp
	$(MPICXX) $(MPICXXFLAGS) -c -o $@ $<

# Object file rules for different search implementations
old-search.o: old-search.cpp
	$(CXX) $(CXXFLAGS) -c -o $@ $<

search-rs.o: search-rs.cpp
	$(CXX) $(CXXFLAGS) -c -o $@ $<

search-sht.o: search-sht.cpp
	$(CXX) $(CXXFLAGS) -c -o $@ $<

install:
	-cp $(EXE) $(BINDIR)
	-strip $(BINDIR)/$(EXE)

uninstall:
	-rm -f $(BINDIR)/$(EXE)

clean:
	-rm -f $(OBJS) $(EXE) $(TEST_OBJS) $(TEST_EXE) $(MPI_OBJS) $(MPI_EXE) $(RS_OBJS) $(RS_EXE) $(SHT_OBJS) $(SHT_EXE)
	-rm -f *.o
