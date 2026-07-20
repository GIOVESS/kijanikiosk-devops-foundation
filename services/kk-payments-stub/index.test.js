const { calculateTotal, applyDiscount } = require('./index');

test('calculateTotal sums item amounts correctly', () => {
  const items = [{ amount: 100 }, { amount: 250 }, { amount: 50 }];
  expect(calculateTotal(items)).toBe(400);
});

test('calculateTotal returns 0 for empty array', () => {
  expect(calculateTotal([])).toBe(0);
});

test('calculateTotal throws on invalid amount', () => {
  expect(() => calculateTotal([{ amount: -5 }])).toThrow(RangeError);
});

test('applyDiscount applies percentage correctly', () => {
  expect(applyDiscount(200, 10)).toBe(180);
});

test('applyDiscount throws on invalid percent', () => {
  expect(() => applyDiscount(100, 150)).toThrow(RangeError);
});

test('deliberate failure - CI pipeline proof', () => {
  expect(1 + 1).toBe(3);
});
