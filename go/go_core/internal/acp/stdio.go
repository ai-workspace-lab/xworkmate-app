package acp

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"sync"

	"xworkmate/go_core/internal/shared"
)

func RunStdio(input io.Reader, output io.Writer) {
	server := NewServer()
	reader := bufio.NewReader(input)
	var writeMu sync.Mutex

	writeMessage := func(message map[string]any) {
		payload, _ := jsonMarshal(message)
		writeMu.Lock()
		defer writeMu.Unlock()
		_, _ = output.Write(append(payload, '\n'))
	}

	for {
		payload, err := readStdioMessage(reader)
		if err != nil {
			if errors.Is(err, io.EOF) {
				return
			}
			writeMessage(shared.ErrorEnvelope(nil, -32700, err.Error()))
			continue
		}
		if len(strings.TrimSpace(string(payload))) == 0 {
			continue
		}

		request, err := shared.DecodeRPCRequest(payload)
		if err != nil {
			writeMessage(shared.ErrorEnvelope(nil, -32700, err.Error()))
			continue
		}
		response, rpcErr := server.handleRequest(request, writeMessage)
		if request.ID == nil {
			continue
		}
		if rpcErr != nil {
			writeMessage(
				shared.ErrorEnvelope(request.ID, rpcErr.Code, rpcErr.Message),
			)
			continue
		}
		writeMessage(shared.ResultEnvelope(request.ID, response))
	}
}

func readStdioMessage(reader *bufio.Reader) ([]byte, error) {
	line, err := reader.ReadString('\n')
	if err != nil {
		return nil, err
	}
	line = strings.TrimSpace(line)
	if line == "" {
		return nil, nil
	}
	if strings.HasPrefix(strings.ToLower(line), "content-length:") {
		var contentLength int
		if _, err := fmt.Sscanf(line, "Content-Length: %d", &contentLength); err != nil {
			if _, err2 := fmt.Sscanf(line, "content-length: %d", &contentLength); err2 != nil {
				return nil, fmt.Errorf("invalid content-length header")
			}
		}
		for {
			headerLine, err := reader.ReadString('\n')
			if err != nil {
				return nil, err
			}
			if strings.TrimSpace(headerLine) == "" {
				break
			}
		}
		body := make([]byte, contentLength)
		if _, err := io.ReadFull(reader, body); err != nil {
			return nil, err
		}
		return body, nil
	}
	return []byte(line), nil
}

func jsonMarshal(message map[string]any) ([]byte, error) {
	return json.Marshal(message)
}
