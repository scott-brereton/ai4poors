// background.js
// Ai4PoorsSafari - Background service worker
//
// Routes messages between content scripts and the native Swift backend.

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    // Handle open_url requests from content script
    if (message.action === 'open_url' && message.url) {
        browser.tabs.create({ url: message.url });
        sendResponse({ ok: true });
        return true;
    }

    if (!message.action || !message.content) {
        sendResponse({ result: 'Error: Invalid message format' });
        return true;
    }

    // Forward to native handler
    browser.runtime.sendNativeMessage(
        'com.example.ai4poors.safari',
        {
            action: message.action,
            content: message.content
        },
        (response) => {
            if (browser.runtime.lastError) {
                sendResponse({
                    result: 'Error: ' + (browser.runtime.lastError.message || 'Native messaging failed')
                });
            } else {
                sendResponse(response || { result: 'No response from backend' });
            }
        }
    );

    // Return true to indicate async response
    return true;
});

// Handle toolbar button click
browser.action.onClicked.addListener((tab) => {
    browser.tabs.sendMessage(tab.id, { action: 'toggle_panel' });
});
