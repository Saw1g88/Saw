let icons="globe.asia.australia",icolor="#6699FF",gptf=false,hideIP=true,cnTimeout=1e3,usTimeout=3e3;if(typeof $argument!=="undefined"&&$argument!==""){const e=getin("$argument");icons=e.icon||icons;icolor=e.icolor||icolor;gptf=e.GPT!=0;hideIP=e.hideIP!=0;cnTimeout=e.cnTimeout||1e3;usTimeout=e.usTimeout||3e3}function getin(){return Object.fromEntries($argument.split("&").map((e=>e.split("="))).map((([e,t])=>[e,decodeURIComponent(t)])))}(async()=>{try{let e="",t="",i="节点信息",n="代理链",o="",s="",l="",c="";const a=await tKey("http://ip-api.com/json/?lang=zh-CN",usTimeout);if(a.status==="success"){console.log("ipapi"+JSON.stringify(a,null,2));let{country:t,countryCode:i,regionName:n,query:s,city:l,org:c,isp:r,as:u,tk:p}=a;e=s;hideIP&&(s=HIP(s));t===l&&(l="");let f=getflag(i)+t+" "+l;o=" \t"+f+"\n落地IP: \t"+s+": "+p+"ms"+"\n落地ISP: \t"+r+"\n落地ASN: \t"+u+""}else{console.log("ild"+JSON.stringify(a));o=""}if(gptf){const e=await tKey("http://chat.openai.com/cdn-cgi/trace",usTimeout);const t=["CN","TW","HK","IR","KP","RU","VE","BY"];if(typeof e!=="string"){let{loc:n,tk:o,warp:s,ip:l}=e,c=t.indexOf(n),a="";if(c==-1){a="GPT: "+n+" ✓"}else{a="GPT: "+n+" ×"}if(s="plus"){s="Plus"}i=a+"       ➟     Priv: "+s+"   "+o+"ms"}else{i="ChatGPT "+e}}const r=await httpAPI();let u,p="";const f=r.requests.slice(0,6);let g=f.filter((e=>/ip-api\.com/.test(e.URL)));if(g.length>0){const e=g[0];c=": "+e.policyName;if(/\(Proxy\)/.test(e.remoteAddress)){u=e.remoteAddress.replace(" (Proxy)","");n=""}else{u="Noip";p="代理链地区:"}}else{u="Noip"}let m=false,d="spe",P=false,y="edtest";isv6=false,cn=true;if(u==="Noip"){m=true}else if(/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(u)){P=true}else if(/^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$/.test(u)){isv6=true}if(u==e){cn=false;p="直连节点:"}else{if(p===""){p="落地地区:"}if(!m||P){const e=await tKey(`https://api-v3.${d}${y}.cn/ip?ip=${u}`,cnTimeout);if(e.code===0&&e.data.country==="中国"){let{province:t,isp:i,city:o,countryCode:l}=e.data,c=e.tk;console.log("ik"+JSON.stringify(e,null,2));cn=true;hideIP&&(u=HIP(u));s="入口国家: \t"+getflag(l)+t+" "+o+"\n入口IP: \t"+u+": "+c+"ms"+"\n入口ISP: \t"+i+n+"\n---------------------\n"}else{cn=false;console.log("ik"+JSON.stringify(e));s="入口IPA Failed\n"}}if((!m||isv6)&&!cn){const e=await tKey(`http://ip-api.com/json/${u}?lang=zh-CN`,usTimeout);if(e.status==="success"){console.log("iai"+JSON.stringify(e,null,2));let{countryCode:t,country:i,city:o,tk:l,isp:c}=e;hideIP&&(u=HIP(u));let a=i+" "+o;s="入口国家: \t"+getflag(t)+a+"\n入口IP: \t"+u+": "+l+"ms"+"\n入口ISP: \t"+c+n+"\n---------------------\n"}else{console.log("iai"+JSON.stringify(e));s="入口IPB Failed\n"}}}$done({title:i+c,content:l+t+s+p+o,icon:icons,"icon-color":icolor})}catch(e){console.log(e.message);$done({title:outgpt+nodeNames,content:local+outbli+outik+outld+zl,icon:icons,"icon-color":icolor})}})(),function e(t,i){if(t.length>i){return t.slice(0,i)}else if(t.length<i){return t.toString().padEnd(i," ")}else{return t}};function sK(e,t){return e.split(" ",t).join(" ").replace(/\.|\,|com|\u4e2d\u56fd/g,"")}function HIP(e){return e.replace(/(\w{1,4})(\.|\:)(\w{1,4}|\*)$/,((e,t,i,n)=>`${"∗".repeat(t.length)}.${"∗".repeat(n.length)}`))}async function httpAPI(e="/v1/requests/recent",t="GET",i=null){return new Promise(((n,o)=>{$httpAPI(t,e,i,(e=>{n(e)}))}))}function getflag(e){const t=e.toUpperCase().split("").map((e=>127397+e.charCodeAt()));return String.fromCodePoint(...t).replace(/🇹🇼/g,"🇨🇳")}async function tKey(e,t){let i=1,o=1;const s=new Promise(((s,l)=>{const c=async a=>{try{const i=await Promise.race([new Promise(((t,i)=>{let n=Date.now();$httpClient.get({url:e},((e,o,s)=>{if(e){i(e)}else{let e=Date.now()-n;let i=o.status;switch(i){case 200:let i=o.headers["Content-Type"];switch(true){case i.includes("application/json"):let n=JSON.parse(s);n.tk=e;t(n);break;case i.includes("text/html"):t("text/html");break;case i.includes("text/plain"):let o=s.split("\n");let l=o.reduce(((t,i)=>{let[n,o]=i.split("=");t[n]=o;t.tk=e;return t}),{});t(l);break;case i.includes("image/svg+xml"):t("image/svg+xml");break;default:t("未知");break}break;case 204:let n={tk:e};t(n);break;case 429:console.log("次数过多");t("次数过多");break;case 404:console.log("404");t("404");break;default:t("nokey");break}}}))})),new Promise(((e,i)=>{setTimeout((()=>i(new Error("timeout"))),t)}))]);if(i){s(i)}else{s("超时");l(new Error(n.message))}}catch(e){if(a<i){o++;c(a+1)}else{s("检测失败, 重试次数"+o);l(e)}}};c(0)}));return s}
