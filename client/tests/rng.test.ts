test('dummy rng', ()=>{
  const rng = (seed:number)=>{ let x = seed|0; return ()=> (x = (x*1664525+1013904223)|0)>>>0; };
  const a = rng(1)(); const b = rng(1)();
  expect(a).toBe(b);
});

