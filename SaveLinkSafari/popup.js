// Saves the current tab to SaveLinks through the native extension handler.
const t = (key, ...subs) => browser.i18n.getMessage(key, subs);

function show(state, title, detail = "") {
    const icon = document.getElementById("icon");
    icon.className = state;
    icon.textContent = state === "ok" ? "✓" : state === "warn" ? "!" : "";
    document.getElementById("title").textContent = title;
    document.getElementById("detail").textContent = detail;
}

async function save() {
    show("spinner", t("saving"));
    const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
    if (!tab || !tab.url || !/^https?:/i.test(tab.url)) {
        show("warn", t("no_page"));
        return;
    }
    try {
        const reply = await browser.runtime.sendNativeMessage("application.id", {
            action: "save",
            url: tab.url,
            title: tab.title || ""
        });
        switch (reply && reply.status) {
            case "saved":
                show("ok", t("saved"), reply.folder ? t("saved_in", reply.folder) : t("opens_next"));
                break;
            case "duplicate":
                show("ok", t("already_saved"));
                break;
            case "limit":
                show("warn", t("limit"));
                break;
            default:
                show("warn", t("error"));
        }
    } catch (error) {
        show("warn", t("error"));
    }
}

save();
