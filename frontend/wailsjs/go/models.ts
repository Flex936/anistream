export namespace main {
	
	export class NextAiringEpisode {
	    episode: number;
	
	    static createFrom(source: any = {}) {
	        return new NextAiringEpisode(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.episode = source["episode"];
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
	    nextAiringEpisode?: NextAiringEpisode;
	
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

