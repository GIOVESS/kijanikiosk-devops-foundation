/**
 * KijaniKiosk Payments Service (stub)
 * Minimal payment total calculator standing in for the real payments logic.
 */

function calculateTotal(items) {
  if (!Array.isArray(items)) {
    throw new TypeError('items must be an array');
  }
  return items.reduce((sum, item) => {
    if (typeof item.amount !== 'number' || item.amount < 0) {
      throw new RangeError(`invalid amount: ${item.amount}`);
    }
    return sum + item.amount;
  }, 0);
}

function applyDiscount(total, percent) {
  if (percent < 0 || percent > 100) {
    throw new RangeError('percent must be between 0 and 100');
  }
  return total - (total * percent) / 100;
}

module.exports = { calculateTotal, applyDiscount };

// deliberate lint fault
const unusedVariable = 42;
