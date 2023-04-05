function _typeof(obj) { "@babel/helpers - typeof"; return _typeof = "function" == typeof Symbol && "symbol" == typeof Symbol.iterator ? function (obj) { return typeof obj; } : function (obj) { return obj && "function" == typeof Symbol && obj.constructor === Symbol && obj !== Symbol.prototype ? "symbol" : typeof obj; }, _typeof(obj); }
import { isNumber } from './utils.js';

/**
 * The LosslessJSON.stringify() method converts a JavaScript value to a JSON string,
 * optionally replacing values if a replacer function is specified, or
 * optionally including only the specified properties if a replacer array is specified.
 *
 * @param value
 * The value to convert to a JSON string.
 *
 * @param [replacer]
 * A function that alters the behavior of the stringification process,
 * or an array of String and Number objects that serve as a whitelist for
 * selecting the properties of the value object to be included in the JSON string.
 * If this value is null or not provided, all properties of the object are
 * included in the resulting JSON string.
 *
 * @param [space]
 * A String or Number object that's used to insert white space into the output
 * JSON string for readability purposes. If this is a Number, it indicates the
 * number of space characters to use as white space; this number is capped at 10
 * if it's larger than that. Values less than 1 indicate that no space should be
 * used. If this is a String, the string (or the first 10 characters of the string,
 * if it's longer than that) is used as white space. If this parameter is not
 * provided (or is null), no white space is used.
 *
 * @param [numberStringifiers]
 * An optional list with additional number stringifiers, for example to serialize
 * a BigNumber. The output of the function must be valid stringified JSON.
 * When `undefined` is returned, the property will be deleted from the object.
 * The difference with using a `replacer` is that the output of a `replacer`
 * must be JSON and will be stringified afterwards, whereas the output of the
 * `numberStringifiers` is already stringified JSON.
 *
 * @returns Returns the string representation of the JSON object.
 */
export function stringify(value, replacer, space, numberStringifiers) {
  var resolvedSpace = resolveSpace(space);
  var replacedValue = typeof replacer === 'function' ? replacer.call({
    '': value
  }, '', value) : value;
  return stringifyValue(replacedValue, '');

  /**
   * Stringify a value
   */
  function stringifyValue(value, indent) {
    if (Array.isArray(numberStringifiers)) {
      var stringifier = numberStringifiers.find(function (item) {
        return item.test(value);
      });
      if (stringifier) {
        var str = stringifier.stringify(value);
        if (typeof str !== 'string' || !isNumber(str)) {
          throw new Error('Invalid JSON number: ' + 'output of a number stringifier must be a string containing a JSON number ' + "(output: ".concat(str, ")"));
        }
        return str;
      }
    }

    // boolean, null, number, string, or date
    if (typeof value === 'boolean' || typeof value === 'number' || typeof value === 'string' || value === null || value instanceof Date || value instanceof Boolean || value instanceof Number || value instanceof String) {
      return JSON.stringify(value);
    }

    // lossless number, the secret ingredient :)
    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
    // @ts-ignore
    if (value && value.isLosslessNumber) {
      return value.toString();
    }

    // BigInt
    if (typeof value === 'bigint') {
      return value.toString();
    }

    // Array
    if (Array.isArray(value)) {
      return stringifyArray(value, indent);
    }

    // Object (test lastly!)
    if (value && _typeof(value) === 'object') {
      return stringifyObject(value, indent);
    }
    return undefined;
  }

  /**
   * Stringify an array
   */
  function stringifyArray(array, indent) {
    if (array.length === 0) {
      return '[]';
    }
    var childIndent = resolvedSpace ? indent + resolvedSpace : undefined;
    var str = resolvedSpace ? '[\n' : '[';
    for (var i = 0; i < array.length; i++) {
      var item = typeof replacer === 'function' ? replacer.call(array, String(i), array[i]) : array[i];
      if (resolvedSpace) {
        str += childIndent;
      }
      if (typeof item !== 'undefined' && typeof item !== 'function') {
        str += stringifyValue(item, childIndent);
      } else {
        str += 'null';
      }
      if (i < array.length - 1) {
        str += resolvedSpace ? ',\n' : ',';
      }
    }
    str += resolvedSpace ? '\n' + indent + ']' : ']';
    return str;
  }

  /**
   * Stringify an object
   */
  function stringifyObject(object, indent) {
    if (typeof object.toJSON === 'function') {
      return stringify(object.toJSON(), replacer, space, undefined);
    }
    var keys = Array.isArray(replacer) ? replacer.map(String) : Object.keys(object);
    if (keys.length === 0) {
      return '{}';
    }
    var childIndent = resolvedSpace ? indent + resolvedSpace : undefined;
    var first = true;
    var str = resolvedSpace ? '{\n' : '{';
    keys.forEach(function (key) {
      var value = typeof replacer === 'function' ? replacer.call(object, key, object[key]) : object[key];
      if (includeProperty(key, value)) {
        if (first) {
          first = false;
        } else {
          str += resolvedSpace ? ',\n' : ',';
        }
        var keyStr = JSON.stringify(key);
        str += resolvedSpace ? childIndent + keyStr + ': ' : keyStr + ':';
        str += stringifyValue(value, childIndent);
      }
    });
    str += resolvedSpace ? '\n' + indent + '}' : '}';
    return str;
  }

  /**
   * Test whether to include a property in a stringified object or not.
   */
  function includeProperty(key, value) {
    return typeof value !== 'undefined' && typeof value !== 'function' && _typeof(value) !== 'symbol';
  }
}

/**
 * Resolve a JSON stringify space:
 * replace a number with a string containing that number of spaces
 */
function resolveSpace(space) {
  if (typeof space === 'number') {
    return ' '.repeat(space);
  }
  if (typeof space === 'string' && space !== '') {
    return space;
  }
  return undefined;
}
//# sourceMappingURL=stringify.js.map