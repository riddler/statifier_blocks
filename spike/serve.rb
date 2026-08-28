# Minimal static file server, Ruby stdlib only (socket). No webrick, no gems.
# Usage: ruby serve.rb <docroot> <port>
require "socket"

root = File.expand_path(ARGV[0] || ".")
port = (ARGV[1] || 8642).to_i

TYPES = {
  ".html" => "text/html; charset=utf-8",
  ".css" => "text/css; charset=utf-8",
  ".js" => "text/javascript; charset=utf-8",
  ".mjs" => "text/javascript; charset=utf-8",
  ".json" => "application/json; charset=utf-8",
  ".svg" => "image/svg+xml",
  ".png" => "image/png",
  ".gif" => "image/gif",
  ".ico" => "image/x-icon"
}.freeze

server = TCPServer.new("127.0.0.1", port)
puts "serving #{root} on http://localhost:#{port}"

loop do
  Thread.start(server.accept) do |sock|
    begin
      request = sock.gets
      next unless request

      # drain headers
      while (line = sock.gets) && line != "\r\n"; end

      path = request.split(" ")[1].to_s.split("?").first
      path = "/index.html" if path == "/"
      file = File.expand_path(File.join(root, path))

      if file.start_with?(root) && File.file?(file)
        body = File.binread(file)
        type = TYPES.fetch(File.extname(file), "application/octet-stream")
        sock.print "HTTP/1.1 200 OK\r\nContent-Type: #{type}\r\n" \
                   "Content-Length: #{body.bytesize}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        sock.write body
      else
        body = "not found"
        sock.print "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\n" \
                   "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
      end
    rescue StandardError
      # per-connection errors are non-fatal
    ensure
      sock.close
    end
  end
end
