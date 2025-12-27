test('assigns a branch', ()=>{
  // Logic unit: prefer balancing A/B
  const pick = (aCount:number,bCount:number)=> aCount<=bCount? 'A':'B';
  expect(pick(0,0)).toBe('A'); expect(pick(1,0)).toBe('B');
});

