CC      = gcc
CFLAGS  = -Wall -Wextra -std=c11 -g -Iinclude
LDFLAGS = -lreadline

SRCS    = src/main.c src/lexer.c src/parser.c src/executor.c src/builtins.c src/jobs.c
OBJS    = $(SRCS:.c=.o)
TARGET  = hsh

.PHONY: all clean test

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

%.o: %.c include/shell.h
	$(CC) $(CFLAGS) -c -o $@ $<

test: $(TARGET)
	bash tests/run_tests.sh

clean:
	rm -f $(OBJS) $(TARGET)
