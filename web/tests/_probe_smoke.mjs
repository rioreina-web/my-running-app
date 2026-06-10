process.env.NODE_ENV = 'test';
try {
  const m = await import('../src/components/coach/workout-helpers.ts');
  console.log('OK: module loaded, exports keys =', Object.keys(m).length);
  const out = m.paceRangeLabel('mp', { type: 'seconds_per_mile', value: 20 }, undefined, { mp: 360 });
  console.log('paceRangeLabel result =', out);
  const nullPace = m.safePaceLabel(undefined, undefined, undefined);
  console.log('safePaceLabel(undef, undef, undef) =', JSON.stringify(nullPace));
  const exactPace = m.safePaceLabel(undefined, undefined, 345);
  console.log('safePaceLabel(undef, undef, 345) =', JSON.stringify(exactPace));
  const range = m.trainingZoneRange('easy', 332);
  console.log('trainingZoneRange(easy, mp=332) =', JSON.stringify(range));
} catch (e) {
  console.error('FAIL:', e.message);
  process.exit(1);
}
