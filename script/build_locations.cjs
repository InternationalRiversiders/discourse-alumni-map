// Reproduce the legacy location catalog without adding a Node runtime to Rails.
// Usage: node script/build_locations.cjs /opt/alumni-map
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const source = process.argv[2];
const requireLegacy = createRequire(path.join(source, 'package.json'));
const { State, City } = requireLegacy('country-state-city');
const cn = requireLegacy('china-area-data');
const countries = [...fs.readFileSync(path.join(source, 'lib/countries.ts'), 'utf8').matchAll(/\{ zh: "([^"]+)", iso: "([^"]+)", lat: ([\d.-]+), lng: ([\d.-]+) \}/g)].map(([,name,code]) => ({name,code}));
const known = [...fs.readFileSync(path.join(source, 'lib/locations.ts'), 'utf8').matchAll(/^  (\[.*\]),?$/gm)].map(([,row]) => JSON.parse(row.replaceAll('undefined','null'))).map(r => ({country:r[2],province:r[3]||'',city:r[4],lat:r[6],lng:r[7]}));
const root = path.resolve(__dirname, '../data/locations');
fs.mkdirSync(root, {recursive:true});
const clean = s => s.replace(/壮族自治区$|回族自治区$|维吾尔自治区$|藏族自治区$/, '').replace(/特别行政区$|省$|市$|自治区$/, '');
for (const c of countries) {
  const states = c.code === 'CN' ? Object.entries(cn['86']).map(([code,name]) => ({code,name:clean(name),cities:[...new Set(Object.values(cn[code]||{}).map(n => n === '市辖区' ? clean(name) : n.replace(/市$/,'')))].map(name => ({name}))})) : State.getStatesOfCountry(c.code).map(s => ({code:s.isoCode,name:s.name,cities:City.getCitiesOfState(c.code,s.isoCode).map(city => ({name:city.name,lat:city.latitude ? Number(city.latitude):null,lng:city.longitude ? Number(city.longitude):null}))}));
  fs.writeFileSync(path.join(root, c.code+'.json'), JSON.stringify(states));
}
fs.writeFileSync(path.join(root,'countries.json'), JSON.stringify(countries));
fs.writeFileSync(path.join(root,'known-cities.json'), JSON.stringify(known));
for (const pkg of ['country-state-city','china-area-data']) fs.copyFileSync(path.join(source,'node_modules',pkg,'LICENSE'),path.join(root,pkg+'-LICENSE'));
console.log(JSON.stringify({countries:countries.length,knownCities:known.length}));
