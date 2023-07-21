function operator(proxies) {
  const counter = {};

  return proxies.map(p => {
    if (!counter[p.name]) counter[p.name] = 0;

    // Increment the counter and format it with leading zero if necessary
    const counterValue = (++counter[p.name]).toString().padStart(2, '0');

    // Concatenate the formatted counter to the name
    p.name = p.name + ' ' + counterValue;
    
    return p;
  });
}
