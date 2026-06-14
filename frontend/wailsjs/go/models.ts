export namespace anilist {
	
	export class NextAiringEpisode {
	    episode: number;
	    airingAt: number;
	
	    static createFrom(source: any = {}) {
	        return new NextAiringEpisode(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.episode = source["episode"];
	        this.airingAt = source["airingAt"];
	    }
	}
	export class AnimeCover {
	    large: string;
	
	    static createFrom(source: any = {}) {
	        return new AnimeCover(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.large = source["large"];
	    }
	}
	export class AnimeTitle {
	    romaji: string;
	    english: string;
	
	    static createFrom(source: any = {}) {
	        return new AnimeTitle(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.romaji = source["romaji"];
	        this.english = source["english"];
	    }
	}
	export class Anime {
	    id: number;
	    title: AnimeTitle;
	    coverImage: AnimeCover;
	    episodes: number;
	    status: string;
	    description: string;
	    nextAiringEpisode: NextAiringEpisode;
	
	    static createFrom(source: any = {}) {
	        return new Anime(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.title = this.convertValues(source["title"], AnimeTitle);
	        this.coverImage = this.convertValues(source["coverImage"], AnimeCover);
	        this.episodes = source["episodes"];
	        this.status = source["status"];
	        this.description = source["description"];
	        this.nextAiringEpisode = this.convertValues(source["nextAiringEpisode"], NextAiringEpisode);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	
	
	export class MediaListEntry {
	    progress: number;
	    media: Anime;
	
	    static createFrom(source: any = {}) {
	        return new MediaListEntry(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.progress = source["progress"];
	        this.media = this.convertValues(source["media"], Anime);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	export class MediaList {
	    name: string;
	    status: string;
	    entries: MediaListEntry[];
	
	    static createFrom(source: any = {}) {
	        return new MediaList(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.name = source["name"];
	        this.status = source["status"];
	        this.entries = this.convertValues(source["entries"], MediaListEntry);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	

}

export namespace config {
	
	export class Resolution {
	    width: number;
	    height: number;
	
	    static createFrom(source: any = {}) {
	        return new Resolution(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.width = source["width"];
	        this.height = source["height"];
	    }
	}

}

export namespace mpv {
	
	export class MpvChapter {
	    title: string;
	    time: number;
	
	    static createFrom(source: any = {}) {
	        return new MpvChapter(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.title = source["title"];
	        this.time = source["time"];
	    }
	}
	export class MpvTrack {
	    id: number;
	    type: string;
	    lang: string;
	    title: string;
	    default: boolean;
	    selected: boolean;
	
	    static createFrom(source: any = {}) {
	        return new MpvTrack(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.type = source["type"];
	        this.lang = source["lang"];
	        this.title = source["title"];
	        this.default = source["default"];
	        this.selected = source["selected"];
	    }
	}
	export class FrontendPayload {
	    duration: number;
	    time_pos: number;
	    paused: boolean;
	    volume: number;
	    muted: boolean;
	    audio_tracks: MpvTrack[];
	    subtitles: MpvTrack[];
	    chapters: MpvChapter[];
	
	    static createFrom(source: any = {}) {
	        return new FrontendPayload(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.duration = source["duration"];
	        this.time_pos = source["time_pos"];
	        this.paused = source["paused"];
	        this.volume = source["volume"];
	        this.muted = source["muted"];
	        this.audio_tracks = this.convertValues(source["audio_tracks"], MpvTrack);
	        this.subtitles = this.convertValues(source["subtitles"], MpvTrack);
	        this.chapters = this.convertValues(source["chapters"], MpvChapter);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	

}

export namespace scraper {
	
	export class TorrentResult {
	    title: string;
	    magnetLink: string;
	    seeders: string;
	    size: string;
	    score: number;
	
	    static createFrom(source: any = {}) {
	        return new TorrentResult(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.title = source["title"];
	        this.magnetLink = source["magnetLink"];
	        this.seeders = source["seeders"];
	        this.size = source["size"];
	        this.score = source["score"];
	    }
	}

}

