// content.js
// Ai4PoorsSafari - Injected into every web page
//
// Creates a floating trigger button and action panel.
// Extracts page content and communicates with the native Swift backend.

(function() {
    'use strict';

    // Prevent double injection
    if (window.__ai4poorsInjected) return;
    window.__ai4poorsInjected = true;

    // Don't inject on extension pages or blank pages
    if (location.protocol === 'safari-extension:' ||
        location.protocol === 'about:' ||
        location.href === 'about:blank') {
        return;
    }

    // ── Configuration ──

    const ACTIONS = [
        { id: 'read',      label: 'Read',      icon: '📖' },
        { id: 'summarize', label: 'Summarize', icon: '📋' },
        { id: 'translate', label: 'Translate', icon: '🌐' },
        { id: 'explain',   label: 'Explain',   icon: '💡' },
        { id: 'extract',   label: 'Key Points', icon: '📌' },
        { id: 'tldr',      label: 'TL;DR',     icon: '⚡' }
    ];

    // ── Create floating trigger button ──

    const trigger = document.createElement('div');
    trigger.id = 'ai4poors-trigger';
    trigger.setAttribute('role', 'button');
    trigger.setAttribute('aria-label', 'Open Ai4Poors AI');
    trigger.setAttribute('tabindex', '0');
    trigger.textContent = '✦';
    document.documentElement.appendChild(trigger);

    // ── Create action panel ──

    const panel = document.createElement('div');
    panel.id = 'ai4poors-panel';
    panel.setAttribute('role', 'dialog');
    panel.setAttribute('aria-label', 'Ai4Poors AI Panel');

    const actionButtonsHTML = ACTIONS.map(a =>
        `<button class="ai4poors-action-btn" data-action="${a.id}" aria-label="${a.label}">
            <span class="ai4poors-action-icon">${a.icon}</span>
            <span class="ai4poors-action-label">${a.label}</span>
        </button>`
    ).join('');

    panel.innerHTML = `
        <div class="ai4poors-panel-inner">
            <div class="ai4poors-panel-header">
                <div class="ai4poors-panel-drag-handle"></div>
                <div class="ai4poors-panel-title-row">
                    <span class="ai4poors-panel-title">✦ Ai4Poors</span>
                    <button id="ai4poors-close" class="ai4poors-close-btn" aria-label="Close panel">✕</button>
                </div>
            </div>
            <div class="ai4poors-panel-body">
                <div id="ai4poors-selection-notice" class="ai4poors-selection-notice" style="display:none;">
                    <span class="ai4poors-selection-icon">✂</span>
                    <span id="ai4poors-selection-text">Using selected text</span>
                </div>
                <div id="ai4poors-actions" class="ai4poors-actions-grid">
                    ${actionButtonsHTML}
                </div>
                <div class="ai4poors-custom-row">
                    <input id="ai4poors-input" type="text" placeholder="Or ask anything about this page..."
                        class="ai4poors-custom-input" autocomplete="off" />
                    <button id="ai4poors-send" class="ai4poors-send-btn" aria-label="Send">↑</button>
                </div>
                <div id="ai4poors-result-container" class="ai4poors-result-container" style="display:none;">
                    <div class="ai4poors-result-header">
                        <span id="ai4poors-result-label" class="ai4poors-result-label">Result</span>
                        <button id="ai4poors-result-close" class="ai4poors-result-close" aria-label="Clear result">✕</button>
                    </div>
                    <div id="ai4poors-result" class="ai4poors-result-content"></div>
                    <div class="ai4poors-result-actions">
                        <button id="ai4poors-copy" class="ai4poors-copy-btn">Copy</button>
                        <button id="ai4poors-open-app" class="ai4poors-open-app-btn" style="display:none;">Open in App</button>
                        <button id="ai4poors-try-archive" class="ai4poors-archive-btn" style="display:none;">Try Archive</button>
                        <button id="ai4poors-back" class="ai4poors-back-btn">&#8592; New Analysis</button>
                    </div>
                </div>
            </div>
        </div>
    `;
    document.documentElement.appendChild(panel);

    // ── Page Content Extraction ──

    function extractPageContent() {
        const result = {
            title: document.title || '',
            url: location.href,
            text: '',
            type: 'page',
            selectedText: null
        };

        // Check for user text selection first
        const selection = window.getSelection().toString().trim();
        if (selection.length > 20) {
            result.selectedText = selection;
            result.type = 'selection';
            updateSelectionNotice(selection);
            return result;
        }

        // Try structured article extraction
        const articleSelectors = [
            'article',
            '[role="main"]',
            'main',
            '.post-content',
            '.article-body',
            '.entry-content',
            '.story-body',
            '.content-body',
            '#article-body',
            '.post-body'
        ];

        for (const selector of articleSelectors) {
            const el = document.querySelector(selector);
            if (el && el.innerText.trim().length > 100) {
                result.text = el.innerText.trim();
                result.type = 'article';
                clearSelectionNotice();
                return result;
            }
        }

        // Try JSON-LD structured data
        const jsonLdScripts = document.querySelectorAll('script[type="application/ld+json"]');
        for (const script of jsonLdScripts) {
            try {
                const data = JSON.parse(script.textContent);
                if (data.articleBody) {
                    result.text = data.articleBody;
                    result.type = 'structured';
                    clearSelectionNotice();
                    return result;
                }
                if (data['@graph']) {
                    const article = data['@graph'].find(item => item.articleBody);
                    if (article) {
                        result.text = article.articleBody;
                        result.type = 'structured';
                        clearSelectionNotice();
                        return result;
                    }
                }
            } catch (e) {
                // Invalid JSON-LD, skip
            }
        }

        // Try meta description as supplement
        const metaDesc = document.querySelector('meta[name="description"]');
        if (metaDesc) {
            result.meta = metaDesc.content;
        }

        // Fallback: full body text (truncated)
        result.text = document.body.innerText.substring(0, 8000).trim();
        result.type = 'page';
        clearSelectionNotice();
        return result;
    }

    // ── Selection Notice ──

    function updateSelectionNotice(text) {
        const notice = document.getElementById('ai4poors-selection-notice');
        const noticeText = document.getElementById('ai4poors-selection-text');
        if (notice && noticeText) {
            const preview = text.length > 60 ? text.substring(0, 60) + '...' : text;
            noticeText.textContent = `Using selected text: "${preview}"`;
            notice.style.display = 'flex';
        }
    }

    function clearSelectionNotice() {
        const notice = document.getElementById('ai4poors-selection-notice');
        if (notice) notice.style.display = 'none';
    }

    // ── Communication with Native Backend ──

    function sendToBackend(action, content) {
        return new Promise((resolve, reject) => {
            const timeout = setTimeout(() => {
                reject(new Error('Request timed out'));
            }, 30000);

            try {
                browser.runtime.sendMessage(
                    { action: action, content: content },
                    (response) => {
                        clearTimeout(timeout);
                        if (browser.runtime.lastError) {
                            reject(new Error(browser.runtime.lastError.message));
                        } else {
                            resolve(response);
                        }
                    }
                );
            } catch (err) {
                clearTimeout(timeout);
                reject(err);
            }
        });
    }

    // ── UI State Management ──

    let panelOpen = false;

    function openPanel() {
        panel.classList.add('ai4poors-panel-open');
        panelOpen = true;
        // Refresh selection state
        extractPageContent();
    }

    function closePanel() {
        panel.classList.remove('ai4poors-panel-open');
        panelOpen = false;
    }

    function showLoading(actionLabel) {
        const resultContainer = document.getElementById('ai4poors-result-container');
        const resultDiv = document.getElementById('ai4poors-result');
        const resultLabel = document.getElementById('ai4poors-result-label');

        // Expand panel and hide actions via CSS class
        panel.classList.add('ai4poors-has-result');

        resultLabel.textContent = actionLabel;
        resultDiv.textContent = 'Analyzing...';
        resultDiv.classList.add('ai4poors-loading');
        resultContainer.style.display = 'flex';
    }

    function showResult(text, isReader) {
        const resultDiv = document.getElementById('ai4poors-result');
        resultDiv.classList.remove('ai4poors-loading');
        if (isReader) {
            resultDiv.classList.add('ai4poors-reader-result');
        } else {
            resultDiv.classList.remove('ai4poors-reader-result');
        }
        // Basic markdown rendering: bold, bullet points, headers
        resultDiv.innerHTML = renderBasicMarkdown(text);

        // Show "Open in App" button for reader results
        const openAppBtn = document.getElementById('ai4poors-open-app');
        if (openAppBtn) {
            openAppBtn.style.display = isReader ? 'block' : 'none';
        }

        // Show "Try Archive" when reader content is suspiciously short (paywall)
        const archiveBtn = document.getElementById('ai4poors-try-archive');
        if (archiveBtn) {
            archiveBtn.style.display = (isReader && text.length < 3000) ? 'block' : 'none';
        }
    }

    function renderBasicMarkdown(text) {
        return text
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
            .replace(/\*(.*?)\*/g, '<em>$1</em>')
            .replace(/^### (.*$)/gm, '<h4 class="ai4poors-md-h4">$1</h4>')
            .replace(/^## (.*$)/gm, '<h3 class="ai4poors-md-h3">$1</h3>')
            .replace(/^# (.*$)/gm, '<h2 class="ai4poors-md-h2">$1</h2>')
            .replace(/^[-•] (.*$)/gm, '<div class="ai4poors-md-li">&#8226; $1</div>')
            .replace(/^\d+\. (.*$)/gm, function(match, p1) {
                return '<div class="ai4poors-md-li">' + match.match(/^\d+/)[0] + '. ' + p1 + '</div>';
            })
            .replace(/`(.*?)`/g, '<code class="ai4poors-md-code">$1</code>')
            .replace(/\n\n/g, '<br><br>')
            .replace(/\n/g, '<br>');
    }

    function showError(message) {
        const resultDiv = document.getElementById('ai4poors-result');
        resultDiv.classList.remove('ai4poors-loading');
        resultDiv.textContent = '⚠ ' + message;
    }

    function clearResult() {
        const resultContainer = document.getElementById('ai4poors-result-container');
        resultContainer.style.display = 'none';

        // Restore actions via CSS class removal
        panel.classList.remove('ai4poors-has-result');

        // Clear reader styling
        const resultDiv = document.getElementById('ai4poors-result');
        if (resultDiv) resultDiv.classList.remove('ai4poors-reader-result');

        // Hide Open in App and Archive buttons
        const openAppBtn = document.getElementById('ai4poors-open-app');
        if (openAppBtn) openAppBtn.style.display = 'none';
        const archiveBtn = document.getElementById('ai4poors-try-archive');
        if (archiveBtn) archiveBtn.style.display = 'none';
    }

    // ── Event Handlers ──

    // Trigger button
    trigger.addEventListener('click', (e) => {
        e.stopPropagation();
        if (panelOpen) {
            closePanel();
        } else {
            openPanel();
        }
    });

    trigger.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault();
            trigger.click();
        }
    });

    // Close button
    document.getElementById('ai4poors-close').addEventListener('click', closePanel);

    // Action buttons
    panel.querySelectorAll('.ai4poors-action-btn').forEach(button => {
        button.addEventListener('click', async () => {
            const action = button.dataset.action;
            const actionLabel = button.querySelector('.ai4poors-action-label').textContent;

            // Reader mode only needs the URL — skip expensive DOM extraction
            const content = action === 'read'
                ? { title: document.title || '', url: location.href, text: '', type: 'page' }
                : extractPageContent();

            showLoading(actionLabel);

            try {
                const response = await sendToBackend(action, content);
                const isReader = response.isReader === true;
                showResult(response.result || 'No result returned', isReader);
            } catch (err) {
                showError(err.message || 'Failed to get response');
            }
        });
    });

    // Custom input
    const inputEl = document.getElementById('ai4poors-input');
    const sendBtn = document.getElementById('ai4poors-send');

    async function handleCustomSubmit() {
        const instruction = inputEl.value.trim();
        if (!instruction) return;

        const content = extractPageContent();
        content.customInstruction = instruction;

        showLoading('Custom');
        inputEl.value = '';

        try {
            const response = await sendToBackend('custom', content);
            showResult(response.result || 'No result returned');
        } catch (err) {
            showError(err.message || 'Failed to get response');
        }
    }

    sendBtn.addEventListener('click', handleCustomSubmit);
    inputEl.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            handleCustomSubmit();
        }
    });

    // Copy button
    document.getElementById('ai4poors-copy').addEventListener('click', () => {
        const text = document.getElementById('ai4poors-result').textContent;
        navigator.clipboard.writeText(text).then(() => {
            const copyBtn = document.getElementById('ai4poors-copy');
            copyBtn.textContent = 'Copied ✓';
            setTimeout(() => { copyBtn.textContent = 'Copy'; }, 2000);
        });
    });

    // Open in Ai4Poors app (reader mode)
    document.getElementById('ai4poors-open-app').addEventListener('click', () => {
        const encoded = encodeURIComponent(location.href);
        window.location.href = 'ai4poors://read?url=' + encoded;
    });

    // Try Archive (paywall fallback) — open via background script
    document.getElementById('ai4poors-try-archive').addEventListener('click', () => {
        browser.runtime.sendMessage({
            action: 'open_url',
            url: 'https://archive.ph/?url=' + encodeURIComponent(location.href)
        });
    });

    // Clear result
    document.getElementById('ai4poors-result-close').addEventListener('click', clearResult);

    // Back / New Analysis button
    document.getElementById('ai4poors-back').addEventListener('click', clearResult);

    // Close on Escape
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && panelOpen) {
            closePanel();
        }
    });

    // Prevent page scroll when panel is open and scrolling result
    panel.addEventListener('wheel', (e) => {
        e.stopPropagation();
    }, { passive: false });

    // Listen for toolbar button toggle from background script
    browser.runtime.onMessage.addListener((message) => {
        if (message && message.action === 'toggle_panel') {
            if (panelOpen) {
                closePanel();
            } else {
                openPanel();
            }
        }
    });

    // Touch handling for mobile — drag to dismiss from header area
    let touchStartY = 0;
    let isDraggingPanel = false;
    const panelInner = panel.querySelector('.ai4poors-panel-inner');

    panel.addEventListener('touchstart', (e) => {
        const header = panel.querySelector('.ai4poors-panel-header');
        const handle = panel.querySelector('.ai4poors-panel-drag-handle');
        // Allow drag from header or handle area
        if ((header && header.contains(e.target)) || (handle && handle.contains(e.target))) {
            touchStartY = e.touches[0].clientY;
            isDraggingPanel = true;
        }
    }, { passive: true });

    panel.addEventListener('touchmove', (e) => {
        if (isDraggingPanel && touchStartY > 0) {
            const diff = e.touches[0].clientY - touchStartY;
            if (diff > 0 && panelInner) {
                // Visual feedback: translate the panel down as user drags
                panelInner.style.transform = 'translateY(' + Math.min(diff, 150) + 'px)';
                panelInner.style.transition = 'none';
            }
            if (diff > 50) {
                // Dismiss threshold reached
                closePanel();
                touchStartY = 0;
                isDraggingPanel = false;
                if (panelInner) {
                    panelInner.style.transform = '';
                    panelInner.style.transition = '';
                }
            }
        }
    }, { passive: true });

    panel.addEventListener('touchend', () => {
        if (isDraggingPanel && panelInner) {
            // Snap back if not dismissed
            panelInner.style.transform = '';
            panelInner.style.transition = 'transform 0.2s ease';
            setTimeout(() => {
                if (panelInner) panelInner.style.transition = '';
            }, 200);
        }
        touchStartY = 0;
        isDraggingPanel = false;
    }, { passive: true });

})();
