# OpenWebUI Chat

A Noctalia Shell plugin for quick slide-in chat with OpenWebUI. Features streaming responses, model selection, persistent chat history, and a chat sidebar for managing conversations.

## Setup

1. Install the plugin through Noctalia Settings → Plugins
2. Configure your OpenWebUI instance:
   - Set the base URL (e.g., `http://localhost:3000`)
   - Login with email/password OR
   - Enter your API key manually
3. Select your preferred model from the dropdown
4. Start chatting!

## IPC Reference
```bash
# Toggle panel
qs -c noctalia-shell ipc call plugin:openwebui-launcher toggle

# Open panel
qs -c noctalia-shell ipc call plugin:openwebui-launcher open

# Close panel
qs -c noctalia-shell ipc call plugin:openwebui-launcher close

# Send message
qs -c noctalia-shell ipc call plugin:openwebui-launcher send "Hello!"

# Set model
qs -c noctalia-shell ipc call plugin:openwebui-launcher setModel "gpt-4o"
```

## Requirements

- Noctalia Shell 4.1.2+
- OpenWebUI instance (local or remote) with API v1
- Valid authentication credentials or API key

## License

MIT

