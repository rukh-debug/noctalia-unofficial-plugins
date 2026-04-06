function extractCoverFileName(manga) {
    if (!manga || !manga.relationships) {
        return "";
    }

    for (var i = 0; i < manga.relationships.length; i++) {
        var rel = manga.relationships[i];
        if (rel.type === "cover_art" && rel.attributes && rel.attributes.fileName) {
            return String(rel.attributes.fileName).trim();
        }
    }

    return "";
}

function mangaCoverUrl(manga, size) {
    if (!manga || !manga.id) {
        return "";
    }

    var fileName = extractCoverFileName(manga);
    if (fileName === "") {
        return "";
    }

    var baseUrl = "https://uploads.mangadex.org/covers/" + manga.id + "/" + fileName;
    if (size === "256" || size === "thumbnail") {
        return baseUrl + ".256.jpg";
    }
    if (size === "512") {
        return baseUrl + ".512.jpg";
    }
    return baseUrl;
}
