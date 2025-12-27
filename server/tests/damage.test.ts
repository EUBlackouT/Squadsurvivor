test('cross-branch damage gets bonus to 15', ()=>{
  const compute = (enemyBranch:'A'|'B', shooter:'A'|'B')=> enemyBranch!==shooter ? 15 : 10;
  expect(compute('A','B')).toBe(15);
  expect(compute('B','A')).toBe(15);
  expect(compute('A','A')).toBe(10);
});

