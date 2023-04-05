function _typeof(obj) { "@babel/helpers - typeof"; return _typeof = "function" == typeof Symbol && "symbol" == typeof Symbol.iterator ? function (obj) { return typeof obj; } : function (obj) { return obj && "function" == typeof Symbol && obj.constructor === Symbol && obj !== Symbol.prototype ? "symbol" : typeof obj; }, _typeof(obj); }
import { isLosslessNumber } from './LosslessNumber.js';
/**
 * Revive a json object.
 * Applies the reviver function recursively on all values in the JSON object.
 * @param json   A JSON Object, Array, or value
 * @param reviver
 *              A reviver function invoked with arguments `key` and `value`,
 *              which must return a replacement value. The function context
 *              (`this`) is the Object or Array that contains the currently
 *              handled value.
 */
export function revive(json, reviver) {
  return reviveValue({
    '': json
  }, '', json, reviver);
}

/**
 * Revive a value
 */
function reviveValue(context, key, value, reviver) {
  if (Array.isArray(value)) {
    return reviver.call(context, key, reviveArray(value, reviver));
  } else if (value && _typeof(value) === 'object' && !isLosslessNumber(value)) {
    // note the special case for LosslessNumber,
    // we don't want to iterate over the internals of a LosslessNumber
    return reviver.call(context, key, reviveObject(value, reviver));
  } else {
    return reviver.call(context, key, value);
  }
}

/**
 * Revive the properties of an object
 */
function reviveObject(object, reviver) {
  Object.keys(object).forEach(function (key) {
    var value = reviveValue(object, key, object[key], reviver);
    if (value !== undefined) {
      object[key] = value;
    } else {
      delete object[key];
    }
  });
  return object;
}

/**
 * Revive the properties of an Array
 */
function reviveArray(array, reviver) {
  for (var i = 0; i < array.length; i++) {
    array[i] = reviveValue(array, i + '', array[i], reviver);
  }
  return array;
}
//# sourceMappingURL=revive.js.map