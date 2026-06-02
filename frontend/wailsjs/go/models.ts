export namespace main {
	
	export class Anime {
	    id: number;
	    // Go type: struct { Romaji string "json:\"romaji\""; English string "json:\"english\"" }
	    title: any;
	    // Go type: struct { Large string "json:\"large\"" }
	    coverImage: any;
	    episodes: number;
	    status: string;
	    description: string;
	
	    static createFrom(source: any = {}) {
	        return new Anime(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.title = this.convertValues(source["title"], Object);
	        this.coverImage = this.convertValues(source["coverImage"], Object);
	        this.episodes = source["episodes"];
	        this.status = source["status"];
	        this.description = source["description"];
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

