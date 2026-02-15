.pragma library

function buildOpenWebUIPayload(model, history) {
    var messages = [];

    // Add conversation history
    for (var i = 0; i < history.length; i++) {
        messages.push(history[i]);
    }

    return {
        "model": model,
        "messages": messages,
        "stream": true
    };
}
