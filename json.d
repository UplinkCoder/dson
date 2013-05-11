/*
Copyright (c) 2013, w0rp <devw0rp@gmail.com>
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

/**

This module defines JSON types, reading, and writing.

parseJSON(inputRange) will convert input ranges (string...) to JSON types.
toJSON(json) will convert JSON types to strings.
writeJSON(outputRange, json) will write JSON to an output range.
toJSON!n and writeJSON!n will write JSON, indented by 'n' spaces.

There is one basic JSON type 'JSON', which has the following properties.

* JSON can be initialised from arrays/maps of JSON, numbers, and strings.
* JSON types can be casted back to arrays/maps, numbers, and strings.
* JSON types can be assigned to with null.
* The type stored can be checked with .is* or with .type
* casting JSON types to bool never fails, so if statements always work.
* cast(bool) is false for empty strings, arrays, and objects.
* cast(bool) is true for non-empty strings, arrays, and objects.
* When the JSON type is an array or object, .length can be read.
* When the JSON type is an array, .length can be written to.
* When the JSON type is an array ~ operations can be used on it.
* When the JSON type is an object, the 'in' operator can be used.
* JSON types can be compared with other types with ==.
* When the JSON type is an array or object, [] operators can be used.
* When the JSON type is an array or object, foreach loops can be used.
* foreach with keys can be used with (string key, value)
* foreach with indices can be used with (size_t index, value)
* foreach for JSON never fails, just never iterates.

*/

module json;

import std.conv;
import std.traits;
import std.range;
import std.array;
import std.algorithm;
import std.string;
import std.uni;
import std.utf : toUTF8;
import std.stdio;
import std.math;

version(unittest) {
    import std.exception;
    import std.math;
}

/**
 * Determine if a type can represent a JSON primitive type.
 */
template isJSONPrimitive(T) {
    enum isJSONPrimitive = __traits(isArithmetic, T)
        || is(T == typeof(null))
        || is(T == string);
}

/**
 * Determine if a type can represent a JSON array.
 */
template isJSONArray(T) {
    enum isJSONArray = isArray!T && isJSON!(ElementType!T);
}

/**
 * Determine if a type can represent a JSON object.
 */
template isJSONObject(T) {
    static if(__traits(isAssociativeArray, T)) {
        enum isJSONObject = is(KeyType!T == string) && isJSON!(ValueType!T);
    } else {
        enum isJSONObject = false;
    }
}

/**
 * Determine if a type can represent any JSON value.
 *
 * The special JSON type is included here.
 */
template isJSON(T) {
    immutable bool isJSON = is(T == JSON) || isJSONPrimitive!T
        || isJSONArray!T || isJSONObject!T;
}

enum JSON_TYPE : byte
{
    NULL, // NULL comes first so the initial type is null.
    BOOL,
    STRING,
    INT,
    FLOAT,
    OBJECT,
    ARRAY
}

/**
 * A union representation of any JSON value.
 */
struct JSON {
private:
    union {
        bool _boolean;
        string _str;
        long _integer;
        real _floating;
        JSON[string] _object;
        JSON[] _array;
    }

    JSON_TYPE _type;
public:
    @safe pure nothrow this(long val) inout {
        _integer = val;
        _type = JSON_TYPE.INT;
    }

    @safe pure nothrow this(bool val) inout {
        _boolean = val;
        _type = JSON_TYPE.BOOL;
    }

    @safe pure nothrow this(real val) inout {
        _floating = val;
        _type = JSON_TYPE.FLOAT;
    }

    @safe pure nothrow this(typeof(null) val) inout {
        _integer = 0;
        _type = JSON_TYPE.NULL;
    }

    @safe pure nothrow this(inout(string) val) inout {
        _str = val;
        _type = JSON_TYPE.STRING;
    }

    @safe pure nothrow this(inout(JSON[]) val) inout {
        _array = val;
        _type = JSON_TYPE.ARRAY;
    }

    @safe pure nothrow this(inout(JSON[string]) val) inout {
        _object = val;
        _type = JSON_TYPE.OBJECT;
    }

    @safe pure nothrow long opAssign(long val) {
        _type = JSON_TYPE.INT;
        return _integer = val;
    }

    @safe pure nothrow bool opAssign(bool val) {
        _type = JSON_TYPE.BOOL;
        return _boolean = val;
    }

    @safe pure nothrow real opAssign(real val) {
        _type = JSON_TYPE.FLOAT;
        return _floating = val;
    }

    @safe pure nothrow typeof(null) opAssign(typeof(null) val) {
        _integer = 0;
        _type = JSON_TYPE.NULL;

        return null;
    }

    @safe pure nothrow string opAssign(string val) {
        _type = JSON_TYPE.STRING;
        return _str = val;
    }

    @safe pure nothrow JSON[] opAssign(JSON[] val) {
        _type = JSON_TYPE.ARRAY;
        return _array = val;
    }

    @safe pure nothrow JSON[string] opAssign(JSON[string] val) {
        _type = JSON_TYPE.OBJECT;
        return _object = val;
    }

    @safe pure nothrow @property JSON_TYPE type() const {
        return _type;
    }


    /**
     * Returns: True if this JSON value contains a numeric type.
     */
    @safe pure nothrow @property bool isNumber() const {
        with(JSON_TYPE) switch(_type) {
        case BOOL, INT, FLOAT:
            return true;
        default:
            return false;
        }
    }

    /**
     * Returns: true if the value is a string.
     */
    @safe pure nothrow @property bool isString() const {
        with(JSON_TYPE) switch(_type) {
        case STRING:
            return true;
        default:
            return false;
        }
    }

    /**
     * Returns: true if this JSON value is null.
     */
    @safe pure nothrow @property bool isNull() const {
        return _type == JSON_TYPE.NULL;
    }

    /**
     * Returns: true if this JSON value is an array.
     */
    @safe pure nothrow @property bool isArray() const {
        return _type == JSON_TYPE.ARRAY;
    }

    /**
     * Returns: true if this JSON value is an object.
     */
    @safe pure nothrow @property bool isObject() const {
        return _type == JSON_TYPE.OBJECT;
    }

    /**
     * Returns: A reference to the JSON array stored in this object.
     * Throws: Exception when the JSON type is not an array.
     */
    @safe pure @property ref inout(JSON[]) array() inout {
        if (_type != JSON_TYPE.ARRAY) {
            throw new Exception("JSON value is not an array!");
        }

        return _array;
    }

    /**
     * Returns: A reference to the JSON object stored in this object.
     * Throws: Exception when the JSON type is not an object.
     */
    @safe pure @property ref inout(JSON[string]) object() inout {
        if (_type != JSON_TYPE.OBJECT) {
            throw new Exception("JSON value is not an object!");
        }

        return _object;
    }

    /**
     * Returns: The length of the inner JSON array or object.
     * Throws: Exception when the JSON type is not an array or object.
     */
    @trusted @property size_t length() const {
        if (_type == JSON_TYPE.ARRAY) {
           return _array.length;
        } else if (_type == JSON_TYPE.OBJECT) {
           return _object.length;
        } else {
            throw new Exception("length called on non array or object type.");
        }
    }

    /**
     * Set the length of the inner JSON array.
     * Throws: Exception when the JSON type is not an array.
     */
    @safe pure @property void length(size_t len) {
        if (_type == JSON_TYPE.ARRAY) {
           _array.length = len;
        } else {
            throw new Exception("Cannot set length on non array!");
        }
    }

    @trusted string toString() const {
        with(JSON_TYPE) final switch (_type) {
        case BOOL:
            return _boolean ? "true" : "false";
        case INT:
            return to!string(_integer);
        case FLOAT:
            return to!string(_floating);
        case STRING:
            return _str;
        case ARRAY:
            return to!string(_array);
        case OBJECT:
            return to!string(_object);
        case NULL:
            return "null";
        }
    }

    // Casting to bool must never throw an exception.
    @trusted nothrow inout(T) opCast(T)() inout if(is(T == bool)) {
        with(JSON_TYPE) final switch (_type) {
        case BOOL:
            return cast(T) _boolean;
        case INT:
            return cast(T) _integer;
        case FLOAT:
            return cast(T) _floating;
        case STRING:
            return _str.length > 0;
        case ARRAY:
            return _array.length > 0;
        case OBJECT:
            try {
                return _object.length > 0;
            } catch (Exception ex) {
                return false;
            }
        case NULL:
            return false;
        }
    }

    // Casting otherwise can throw, but is pure.
    @trusted pure inout(T) opCast(T)() inout if(!is(T == bool)) {
        static if (__traits(isArithmetic, T)) {
            with(JSON_TYPE) switch (_type) {
            case BOOL:
                return cast(T) _boolean;
            case INT:
                return cast(T) _integer;
            case FLOAT:
                return cast(T) _floating;
            default:
                throw new Exception("cast to number failed!");
            }
        } else static if (is(T == string)) {
            if (_type != JSON_TYPE.STRING) {
                throw new Exception("cast(string) failed!");
            }

            return _str;
        } else static if(is(T == JSON[])) {
            if (_type != JSON_TYPE.ARRAY) {
                throw new Exception("JSON value is not an array!");
            }

            return _array;
        } else static if(is(T == JSON[string])) {
            if (_type != JSON_TYPE.OBJECT) {
                throw new Exception("JSON value is not an object!");
            }

            return _object;
        } else {
            static assert(false, "Unsupported cast from JSON!");
        }
    }

    @safe pure
    JSON opBinary(string op : "~", T)(T val) {
        static if(is(T == JSON)) {
            // We can avoid a copy for JSON types.
            return JSON(array ~ val);
        } else {
            return JSON(array ~ JSON(val));
        }
    }

    // Defining put makes this an output range.
    @safe pure
    void put(T)(T val) {
        static if(is(T == JSON)) {
            array ~= val;
        } else {
            array ~= JSON(val);
        }
    }

    @safe pure
    void opOpAssign(string op : "~", T)(T val) {
        put(val);
    }

    @safe pure ref inout(JSON) opIndex(size_t index) inout {
        return array[index];
    }

    @safe pure ref inout(JSON) opIndex(string key) inout {
        return object[key];
    }

    @safe pure void opIndexAssign(T)(T value, size_t index) {
        array[index] = value;
    }

    @trusted pure void opIndexAssign(T)(T value, string key) {
        object[key] = value;
    }

    @trusted pure inout(JSON*)
    opBinaryRight(string op : "in") (string key) inout {
        return key in object;
    }

    @trusted int opApply(int delegate(ref JSON val) dg) {
        int result;

        if (_type == JSON_TYPE.ARRAY) {
            foreach(ref val; _array) {
                if((result = dg(val)) > 0) {
                    break;
                }
            }
        } else if (_type == JSON_TYPE.OBJECT) {
            foreach(ref val; _object) {
                if((result = dg(val)) > 0) {
                    break;
                }
            }
        }

        return result;
    }

    @trusted int opApply(int delegate(string key, ref JSON val) dg) {
        int result;

        if (_type == JSON_TYPE.OBJECT) {
            foreach(key, ref val; _object) {
                if((result = dg(key, val)) > 0) {
                    break;
                }
            }
        } else if(_type == JSON_TYPE.ARRAY) {
            foreach(index, ref val; _array) {
                if((result = dg(to!string(index), val)) > 0) {
                    break;
                }
            }
        }

        return result;
    }

    @trusted int opApply(int delegate(size_t index, ref JSON val) dg) {
        if(_type == JSON_TYPE.OBJECT) {
            throw new Exception("index-value foreach not supported for "
                ~ "objects!");
        }

        int result;

        if (_type == JSON_TYPE.ARRAY) {
            foreach(index, ref val; _array) {
                if((result = dg(index, val)) > 0) {
                    break;
                }
            }
        }

        return result;
    }

    @trusted int opApplyReverse(int delegate(ref JSON val) dg) {
        if (_type == JSON_TYPE.OBJECT) {
            // Map are unordered, so the same code for foreach can be used.
            return opApply(dg);
        }

        int result;

        if (_type == JSON_TYPE.ARRAY) {
            foreach_reverse(ref val; _array) {
                if((result = dg(val)) > 0) {
                    break;
                }
            }
        }

        return result;
    }

    @trusted int opApplyReverse(int delegate(string key, ref JSON val) dg) {
        if (_type == JSON_TYPE.OBJECT) {
            return opApply(dg);
        }

        int result;

        if(_type == JSON_TYPE.ARRAY) {
            foreach_reverse(index, ref val; _array) {
                if((result = dg(to!string(index), val)) > 0) {
                    break;
                }
            }
        }

        return result;
    }

    @trusted int opApplyReverse(int delegate(size_t index, ref JSON val) dg) {
        if(_type == JSON_TYPE.OBJECT) {
            throw new Exception("index-value foreach_reverse not supported "
                ~ "for objects!");
        }

        int result;

        if (_type == JSON_TYPE.ARRAY) {
            foreach_reverse(index, ref val; _array) {
                if((result = dg(index, val)) > 0) {
                    break;
                }
            }
        }

        return result;
    }

    // TODO: @safe pure?
    @trusted nothrow bool opEquals(T)(inout(T) other) inout
    if(!is(T == typeof(null))) {
        static if(is(T == JSON)) {
            if (_type != other._type) {
                return false;
            }

            with(JSON_TYPE) final switch (_type) {
            case BOOL:
                return _boolean == other._boolean;
            case INT:
                return _integer == other._integer;
            case FLOAT:
                return _floating == other._floating;
            case STRING:
                return _str == other._str;
            case ARRAY:
                return _array == other._array;
            case OBJECT:
                return _object == other._object;
            case NULL:
                // The types match, so this is true.
                return true;
            }
        } else static if(is(T : string)) {
            return _type == JSON_TYPE.STRING && _str == other;
        } else static if(isJSONArray!T) {
            if (_type != JSON_TYPE.ARRAY || _array.length != other.length) {
                return false;
            }

            for (size_t i = 0; i < _array.length; ++i) {
                if (_array[0] != other[0]) {
                    return false;
                }
            }

            return true;
        } else static if(isJSONObject!T) {
            if (_type != JSON_TYPE.OBJECT || _object.length != other.length) {
                return false;
            }

            foreach(key, val; _object) {
                auto other_val_p = key in other;

                if (!other_val_p || val != *other_val_p) {
                    return false;
                }
            }

            return true;
        } else static if(__traits(isArithmetic, T)) {
            with(JSON_TYPE) switch (_type) {
            case BOOL:
                return _boolean == other;
            case INT:
                return _integer == other;
            case FLOAT:
                return _floating == other;
            default:
                return false;
            }
        } else {
            static assert(false, "No match for JSON opEquals!");
        }
    }

    // TODO: opCmp
}

/**
 * Returns: A new JSON object.
 */
@safe pure nothrow JSON jsonObject() {
    JSON object;
    object._object = null;
    object._type = JSON_TYPE.OBJECT;

    return object;
}

/**
 * Returns: A new JSON array.
 */
@safe pure nothrow JSON jsonArray() {
    JSON array;
    array._array = null;
    array._type = JSON_TYPE.ARRAY;

    return array;
}

/**
 * Given an input range of JSON convertable values,
 * produce an array of JSON values.
 *
 * Returns: A new JSON array contains values from the input range.
 */
@safe pure nothrow JSON toJSONArray(InputRange)(InputRange inputRange)
if (isInputRange!InputRange && isJSON!(ElementType!InputRange)) {
    alias ElementType!InputRange E;

    JSON array = jsonArray();

    foreach(val; inputRange) {
        try {
            static if (isJSONPrimitive!E
            || is(E == JSON)
            || is(E == JSON[])
            || is(E == JSON[string])) {
                // The struct's handling of conversion will work here.
                array ~= val;
            } else {
                array ~= convertJSON(val);
            }
        } catch (Exception ex) {
            throw new Error(ex.msg);
        }
    }

    return array;
}

/**
 * Given a value attempt to convert that value into a JSON value.
 *
 * This function can be useful for initialising a JSON value from a literal.
 */
JSON convertJSON(T)(T object) {
    static if (is(T == JSON)) {
        // No conversion neeeded.
        return object;
    } else static if(is(T == JSON[]) || is(T == JSON[string])
        || isJSONPrimitive!T) {
        // This is a straight conversion.
        return JSON(object);
    } else static if(isJSONArray!T)  {
        auto arr = new JSON[](object.length);

        for (size_t i = 0; i < object.length; ++i) {
            arr[i] = convertJSON(object[i]);
        }

        return JSON(arr);
    } else static if(isJSONObject!T) {
        JSON[string] map;

        foreach(key, val; object) {
            map[key] = convertJSON(val);
        }

        return JSON(map);
    } else {
        static assert(false, "Invalid type for convertJSON!");
    }
}

class JSONException : Exception {
    this(string msg) {
        super(msg);
    }
}

class JSONWriteException : JSONException {
    this(string msg) {
        super(msg);
    }
}

class JSONParseException : JSONException {
    public const long line;
    public const long col;

    this(string reason, long line, long col) {
        this.line = line;
        this.col = col;

        super(reason ~ " at line " ~ to!string(line)
            ~ " column " ~ to!string(col) ~ "!");
    }
}

private void newline(T)(T outRange) {
    outRange.put('\n');
}

private void indent(T)(T outRange, int spaces) {
    repeat(' ').take(spaces).copy(outRange);
}

/**
 * Given a string to write to, write the given string as a valid JSON string.
 *
 * Control characters found in the string will be either escaped or skipped.
 */
private void writeJSONString(T)(T outRange, string str) {
    outRange.put('"');

    foreach(dchar c; str) {
        switch (c) {
        case '"':
            copy(`\"`, outRange);
        break;
        case '\\':
            copy(`\\`, outRange);
        break;
        case '/':
            copy(`\/`, outRange);
        break;
        case '\b':
            copy(`\b`, outRange);
        break;
        case '\f':
            copy(`\f`, outRange);
        break;
        case '\n':
            copy(`\n`, outRange);
        break;
        case '\r':
            copy(`\r`, outRange);
        break;
        case '\t':
            copy(`\t`, outRange);
        break;
        default:
            // We'll just skip control characters.
            if (!isControl(c)) {
                outRange.put(c);
            } else {
                // We really must complain here. This is because control
                // character, the most obvious of which being null, can
                // break other readers in terrible ways.
                throw new JSONWriteException("Invalid control character "
                    ~ "found in string!");
            }
        }
    }

    outRange.put('"');
}

/**
 * Given a string to write to, write the JSON array to the string.
 */
private void writeJSONArray(int spaces, T)
(T outRange, in JSON[] array, int level) {
    outRange.put('[');

    for (size_t i = 0; i < array.length; ++i) {
        if (i != 0) {
            outRange.put(',');
        }

        static if (spaces > 0) {
            newline(outRange);
            indent(outRange, spaces * (level + 1));
        }

        writePrettyJSON!spaces(outRange, array[i], level + 1);
    }

    static if (spaces > 0) {
        if (array.length > 0) {
            newline(outRange);

            if (level > 0) {
                indent(outRange, spaces * level);
            }
        }
    }

    outRange.put(']');
}

/**
 * Given a string to write to, write the JSON object to the string.
 */
private void writeJSONObject(int spaces, T)
(T outRange, in JSON[string] object, int level) {
    outRange.put('{');

    bool first = true;

    foreach(key, val; object) {
        if (!first) {
            outRange.put(',');
        }

        static if (spaces > 0) {
            newline(outRange);
            indent(outRange, spaces * (level + 1));
        }

        writeJSONString(outRange, key);

        outRange.put(':');

        static if (spaces > 0) {
            outRange.put(' ');
        }

        writePrettyJSON!spaces(outRange, val, level + 1);

        first = false;
    }

    static if (spaces > 0) {
        if (!first) {
            newline(outRange);

            if (level > 0) {
                indent(outRange, spaces * level);
            }
        }
    }

    outRange.put('}');
}


/**
 * Given a string to write to, write the JSON value to the string.
 */
private void writePrettyJSON (int spaces = 0, T)
(T outRange, in JSON json, int level = 0) {
    with(JSON_TYPE) final switch (json.type) {
    case NULL:
        outRange.put("null");
    break;
    case BOOL:
        outRange.put(json._boolean ? "true" : "false");
    break;
    case INT:
        copy(to!string(json._integer), outRange);
    break;
    case FLOAT:
        copy(to!string(json._floating), outRange);
    break;
    case STRING:
        writeJSONString(outRange, json._str);
    break;
    case ARRAY:
        writeJSONArray!spaces(outRange, json._array, level);
    break;
    case OBJECT:
        writeJSONObject!spaces(outRange, json._object, level);
    break;
    }
}

/**
 * Given an output range to write to, write the JSON value to the range.
 */
void writeJSON(int spaces = 0, T) (in JSON json, T outRange)
if(isOutputRange!(T, dchar)) {
    static assert(spaces >= 0, "Negative number of spaces for writeJSON.");

    writePrettyJSON!(spaces, T)(outRange, json);
}

/**
 * Given a file to write to, write the JSON value to the file.
 */
void writeJSON(int spaces = 0)(in JSON json, File file) {
    writeJSON!spaces(json, file.lockingTextWriter);
}

/**
 * Given a JSON value, create a string representing the JSON value.
 */
string toJSON(int spaces = 0)(in JSON json) {
    auto result = appender!string();

    writeJSON!(spaces)(json, result);

    return result.data();
}

private struct JSONReader(InputRange) {
    InputRange jsonRange;
    long line = 1;
    long col = 1;

    this(InputRange jsonRange) {
        this.jsonRange = jsonRange;
    }

    auto complaint(string reason) {
        return new JSONParseException(reason, line, col);
    }

    bool empty() {
        return jsonRange.empty();
    }

    void popFront() {
        ++col;

        scope(failure) --col;

        try {
            jsonRange.popFront();
        } catch {
            throw complaint("Unexpected end of input");
        }
    }

    auto front() {
        try {
            return jsonRange.front();
        } catch {
            throw complaint("Unexpected end of input");
        }
    }

    auto moveFront() {
        ++col;

        scope(failure) --col;

        try {
            auto c = jsonRange.front();
            jsonRange.popFront();

            return c;
        } catch {
            throw complaint("Unexpected end of input");
        }
    }

    void skipWhitespace(bool last = false)() {
        while (true) {
            // empty checks only need to happen when reading whitespace
            // at the end of the stream.
            static if (last) {
                if (empty()) {
                    return;
                }
            }

            if (!isWhite(front())) {
                return;
            }

            // Accept \n, \r, or \r\n for newlines.
            // Skip every other whitespace character.
            switch (moveFront()) {
            case '\r':
                static if (last) {
                    if (!empty() && front() == '\n') {
                        popFront();
                    }
                } else {
                    if (front() == '\n') {
                        popFront();
                    }
                }
            case '\n':
                ++line;
                col = 1;
            default:
            }
        }
    }

    string parseString() {
        auto result = appender!string();

        if (moveFront() != '"') {
            throw complaint("Expected \"");
        }

        loop: while (true) {
            auto c = moveFront();

            switch (c) {
            case '"':
                // End of the string.
                break loop;
            case '\\':
                switch (moveFront()) {
                case '"':
                     result.put('"');
                break;
                case '\\':
                     result.put('\\');
                break;
                case '/':
                     result.put('/');
                break;
                case 'b':
                     result.put('\b');
                break;
                case 'f':
                     result.put('\f');
                break;
                case 'n':
                     result.put('\n');
                break;
                case 'r':
                     result.put('\r');
                break;
                case 't':
                     result.put('\t');
                break;
                case 'u':
                    dchar val = 0;

                    foreach_reverse(i; 0 .. 4) {
                        dchar adjust;

                        switch (front()) {
                        case '0': .. case '9':
                            adjust = '0';
                        break;
                        case 'a': .. case 'f':
                            adjust = 'a' - 10;
                        break;
                        case 'A': .. case 'F':
                            adjust = 'A' - 10;
                        break;
                        default:
                            throw complaint("Expected a hex character");
                        break;
                        }

                        val += (moveFront() - adjust) << (4 * i);

                    }

                    char[4] buf;

                    result.put(toUTF8(buf, val));
                break;
                default:
                    throw complaint("Invalid escape character");
                break;
                }
            break;
            default:
                // We'll just skip control characters.
                if (!isControl(c)) {
                    result.put(c);
                } else {
                }
            break;
            }
        }

        return result.data();
    }

    JSON parseNumber() {
        enum byte NEGATIVE = 1;
        enum byte EXP_NEGATIVE = 2;

        long integer   = 0;
        long remainder = 0;
        short exponent = 0;
        byte signInfo  = 0;

        // Accumulate digits reading left-to-right in a number.
        void parseDigits(T)(ref T accum) {
            while (!empty()) {
                switch(front()) {
                case '0': .. case '9':
                    accum = cast(T) (accum * 10 + (moveFront() - '0'));

                    if (accum < 0) {
                        throw complaint("overflow error!");
                    }
                break;
                default:
                    return;
                }
            }
        }

        if (front() == '-') {
            popFront();

            signInfo = NEGATIVE;
        }

        if (front() == '0') {
            popFront();
        }

        parseDigits(integer);

        if (!empty() && front() == '.') {
            popFront();

            parseDigits(remainder);
        }

        if (!empty() && (front() == 'e' || front() == 'E')) {
            popFront();

            switch (front()) {
            case '-':
                signInfo |= EXP_NEGATIVE;
            case '+':
                popFront();
            default:
            break;
            }

            parseDigits(exponent);
        }

        // NOTE: -0 becomes +0.
        if (remainder == 0 && exponent == 0) {
            // It's an integer.
            return JSON(signInfo & NEGATIVE ? -integer : integer);
        }

        real whole = cast(real) integer;

        if (remainder != 0) {
            // Add in the remainder.
            whole += remainder / (10.0 ^^ (floor(log10(remainder)) + 1));
        }

        if (signInfo & NEGATIVE) {
            whole = -whole;
        }

        if (exponent != 0) {
            // Raise the whole number to the power of the exponent.
            return JSON(whole * (10.0 ^^
                (signInfo & EXP_NEGATIVE ? -exponent : exponent)));
        }


        return JSON(whole);
    }

    JSON[] parseArray() {
        JSON[] arr;

        popFront();

        skipWhitespace();

        if (front() == ']') {
            popFront();
            return arr;
        }

        while (true) {
            arr ~= parseValue();

            skipWhitespace();

            if (front() == ']') {
                // We hit the end of the array
                popFront();
                break;
            }

            if (moveFront() != ',') {
                throw complaint("Expected ]");
            }

            skipWhitespace();
        }

        return arr;
    }

    JSON[string] parseObject() {
        JSON[string] obj;

        popFront();

        skipWhitespace();

        if (front() == '}') {
            popFront();

            return obj;
        }

        while (true) {
            string key = parseString();

            skipWhitespace();

            if (moveFront() != ':') {
                throw complaint("Expected :");
            }

            skipWhitespace();

            obj[key] = parseValue();

            skipWhitespace();

            if (front() == '}') {
                // We hit the end of the object.
                popFront();
                break;
            }

            if (moveFront() != ',') {
                throw complaint("Expected }");
            }

            skipWhitespace();
        }

        return obj;
    }

    void parseChars(string matching)() {
        foreach(c; matching) {
            if (moveFront() != c) {
                throw complaint("Invalid input");
            }
        }
    }

    JSON parseValue() {
        switch (front()) {
        case 't':
            popFront();

            parseChars!"rue"();

            return JSON(true);
        case 'f':
            popFront();

            parseChars!"alse"();

            return JSON(false);
        case 'n':
            popFront();

            parseChars!"ull"();

            return JSON(null);
        case '{':
            return JSON(parseObject());
        break;
        case '[':
            return JSON(parseArray());
        break;
        case '"':
            return JSON(parseString());
        case '-': case '0': .. case '9':
            return parseNumber();
        default:
            throw complaint("Invalid input");
        }
    }

    JSON parseJSON() {
        skipWhitespace();

        JSON val = parseValue();

        if (!empty()) {
            skipWhitespace!true();

            if (!empty()) {
                throw complaint("Trailing character found");
            }
        }

        return val;
    }
}

JSON parseJSON(InputRange)(InputRange jsonRange)
if(isInputRange!InputRange && is(ElementType!InputRange : dchar)) {
    return JSONReader!InputRange(jsonRange).parseJSON();
}

JSON parseJSON(InputRange)(InputRange jsonRange)
if(isInputRange!InputRange && isInputRange!(ElementType!InputRange)
&& is(ElementType!(ElementType!InputRange) : dchar)) {
    return parseJSON!InputRange(joiner(jsonRange));
}

JSON parseJSON(size_t chunkSize = 4096)(File file) {
    return parseJSON(file.byChunk(chunkSize));
}

// TODO: immutable JSON?
// TODO: This caused a RangeViolation: obj["a"] ~= 347;

// Test the templates.
unittest {
    assert(isJSONPrimitive!(typeof(null)));
    assert(isJSONPrimitive!bool);
    assert(isJSONPrimitive!int);
    assert(isJSONPrimitive!uint);
    assert(isJSONPrimitive!real);
    assert(isJSONPrimitive!string);
}

unittest {
    assert(isJSON!(typeof(null)));
    assert(isJSON!bool);
    assert(isJSON!int);
    assert(isJSON!uint);
    assert(isJSON!real);
    assert(isJSON!string);
}

unittest {
    assert(isJSONArray!(string[]));
    assert(isJSONArray!(int[]));
    assert(isJSONArray!(int[][]));
    assert(isJSONArray!(string));
    assert(isJSONArray!(string[][][]));
    assert(isJSONArray!(int[string][][]));
    assert(!isJSONArray!int);
    assert(!isJSONArray!bool);
    assert(!isJSONArray!(typeof(null)));
}

unittest {
    assert(isJSONObject!(int[string]));
    assert(!isJSONObject!(string[bool]));
    assert(isJSONObject!(real[string]));
    assert(isJSONObject!(int[][string]));
}

// Test type return values.
unittest {
    bool x = true;
    JSON j = x;

    assert(j.type == JSON_TYPE.BOOL);
}

unittest {
    int x = 3;
    JSON j = x;

    assert(j.type == JSON_TYPE.INT);
}

unittest {
    float x = 7.3;
    JSON j = x;

    assert(j.type == JSON_TYPE.FLOAT);
}

unittest {
    string x = "";
    JSON j = x;

    assert(j.type == JSON_TYPE.STRING);
}

unittest {
    JSON[] x;
    JSON j = x;

    assert(j.type == JSON_TYPE.ARRAY);
}

unittest {
    JSON[2] x;
    JSON j = x;

    assert(j.type == JSON_TYPE.ARRAY);
}

unittest {
    JSON[string] x;
    JSON j = x;

    assert(j.type == JSON_TYPE.OBJECT);
}

unittest {
    JSON j = null;

    assert(j.type == JSON_TYPE.NULL);
}

// It's important to make sure than normal assignment still
// works properly.
unittest {
    JSON j1;
    JSON j2 = j1;

    assert(j2.type == JSON_TYPE.NULL);
}

// Test valid boolean conversions

unittest {
    bool x = false;
    JSON j = x;

    assert(cast(bool) j == false);
}

unittest {
    bool x = true;
    JSON j = x;

    assert(cast(bool) j == true);
}

unittest {
    int x = 0;
    JSON j = x;

    assert(cast(bool) j == false);
}

unittest {
    int x = -2;
    JSON j = x;

    assert(cast(bool) j == true);
}

unittest {
    float x = 0;
    JSON j = x;

    assert(cast(bool) j == false);
}

unittest {
    float x = 2;
    JSON j = x;

    assert(cast(bool) j == true);
}

// Test special boolean conversions.

unittest {
    string x;
    JSON j = x;

    assert(cast(bool) j == false);
}

unittest {
    string x = "wat";
    JSON j = x;

    assert(cast(bool) j == true);
}

unittest {
    JSON[] x;
    JSON j = x;

    assert(cast(bool) j == false);
}

unittest {
    JSON[] x;
    x.length = 1;
    JSON j = x;

    assert(cast(bool) j == true);
}

unittest {
    JSON[string] x;
    JSON j = x;

    assert(cast(bool) j == false);
}

unittest {
    JSON[string] x;
    x["wat"] = null;
    JSON j = x;

    assert(cast(bool) j == true);
}

unittest {
    JSON j = null;

    assert(cast(bool) j == false);
}

// Test valid signed integer conversions
unittest {
    bool x = false;
    JSON j = x;

    assert(cast(long) j == 0);
}

unittest {
    bool x = true;
    JSON j = x;

    assert(cast(int) j == 1);
}

unittest {
    int x = 0;
    JSON j = x;

    assert(cast(byte) j == 0);
}

unittest {
    int x = -2;
    JSON j = x;

    assert(cast(short) j == -2);
}

unittest {
    float x = 0;
    JSON j = x;

    assert(cast(int) j == 0);
}

unittest {
    float x = 2;
    JSON j = x;

    assert(cast(int) j == 2);
}

// Test invalid signed integer conversions.

unittest {
    string x;
    JSON j = x;

    assertThrown(cast(int) j);
}

unittest {
    JSON[] x;
    JSON j = x;

    assertThrown(cast(int) j);
}

unittest {
    JSON[string] x;
    JSON j = x;

    assertThrown(cast(int) j);
}

// Test valid unsigned integer conversions
unittest {
    int x = -2;
    JSON j = x;

    assert(cast(ulong) j == cast(ulong) x);
}

unittest {
    float x = 0;
    JSON j = x;

    assert(cast(ulong) j == 0);
}

// Test invalid unsigned integer conversions.

unittest {
    string x;
    JSON j = x;

    assertThrown(cast(ulong) j);
}

unittest {
    JSON[] x;
    JSON j = x;

    assertThrown(cast(ulong) j);
}

unittest {
    JSON[string] x;
    JSON j = x;

    assertThrown(cast(ulong) j);
}

// Test valid real conversions
unittest {
    bool x = false;
    JSON j = x;

    assert(cast(real) j == 0.0);
}

unittest {
    bool x = true;
    JSON j = x;

    assert(cast(real) j == 1.0);
}

unittest {
    int x = 33;
    JSON j = x;

    assert(cast(real) j == 33.0);
}

unittest {
    int x = -2;
    JSON j = x;

    assert(cast(real) j == -2.0);
}

unittest {
    float x = 0;
    JSON j = x;

    assert(cast(real) j == 0);
}

unittest {
    float x = 2.5;
    JSON j = x;

    assert(approxEqual(cast(real) j, 2.5, 0.001));
}

// Test invalid real conversions.

unittest {
    string x;
    JSON j = x;

    assertThrown(cast(real) j);
}

unittest {
    JSON[] x;
    JSON j = x;

    assertThrown(cast(real) j);
}

unittest {
    JSON[string] x;
    JSON j = x;

    assertThrown(cast(real) j);
}

// Test valid string casting.
unittest {
    JSON x = "wat";

    assert(cast(string) x == "wat");
}

// Test invalid string casting.
unittest {
    JSON x;

    assertThrown(cast(string) x);
}

unittest {
    JSON x = 2u;

    assertThrown(cast(string) x);
}

unittest {
    JSON x = -2;

    assertThrown(cast(string) x);
}

unittest {
    JSON x = true;

    assertThrown(cast(string) x);
}

unittest {
    JSON[] arr;
    JSON x = arr;

    assertThrown(cast(string) x);
}

unittest {
    JSON[string] obj;
    JSON x = obj;

    assertThrown(cast(string) x);
}

// Test toString()
unittest {
    bool x = false;
    JSON j = x;

    assert(j.toString() == "false");
}

unittest {
    bool x = true;
    JSON j = x;

    assert(j.toString() == "true");
}

unittest {
    int x = 33;
    JSON j = x;

    assert(j.toString() == "33");
}

unittest {
    int x = -2;
    JSON j = x;

    assert(j.toString() == "-2");
}

unittest {
    uint x = 0;
    JSON j = x;

    assert(j.toString() == "0");
}

unittest {
    uint x = 25;
    JSON j = x;

    assert(j.toString() == "25");
}

unittest {
    float x = 0;
    JSON j = x;

    assert(j.toString() == "0");
}

unittest {
    float x = 2.5;
    JSON j = x;

    assert(j.toString() == "2.5");
}

unittest {
    string x = "abc";
    JSON j = x;

    assert(j.toString() == "abc");
}

// Test JSON -> JSON cast
unittest {
    JSON x;
    JSON y = cast(JSON) x;
}

// Test valid JSON -> JSON[] cast
unittest {
    JSON[] arr;
    JSON x = arr;

    assert(cast(JSON[]) x == arr);
}

// Test invalid JSON -> JSON[] cast
unittest {
    JSON x;

    assertThrown(cast(JSON[]) x);
}

// Test valid JSON -> JSON[string] cast
unittest {
    JSON[string] map;
    JSON x = map;

    assert(cast(JSON[string]) x == map);
}

// Test invalid JSON -> JSON[string] cast
unittest {
    JSON x;

    assertThrown(cast(JSON[string]) x);
}

// Test that casting to a class doesn't even compile
unittest {
    class Test() {}
    JSON x;

    static if(__traits(compiles, cast(Test) x)) {
        assert(false);
    }
}

// Test .array
unittest {
    bool b = true;
    int n = 1;
    real r = 1.0;
    string str = "";
    JSON[] arr;
    JSON[string] obj;

    JSON j;
    assertThrown(j.array);

    j = b;
    assertThrown(j.array);

    j = n;
    assertThrown(j.array);

    j = r;
    assertThrown(j.array);

    j = str;
    assertThrown(j.array);

    j = arr;
    assert(j.array == arr);

    j = obj;
    assertThrown(j.array);
}

// Test .object
unittest {
    bool b = true;
    int n = 1;
    real r = 1.0;
    string str = "";
    JSON[] arr;
    JSON[string] obj;

    JSON j;
    assertThrown(j.object);

    j = b;
    assertThrown(j.object);

    j = n;
    assertThrown(j.object);

    j = r;
    assertThrown(j.object);

    j = str;
    assertThrown(j.object);

    j = arr;
    assertThrown(j.object);

    j = obj;
    assert(j.object == obj);
}

// Test isNumber
unittest {
    bool b = true;
    int n = 1;
    real r = 1.0;
    string str = "";
    JSON[] arr;
    JSON[string] obj;

    JSON j;
    assert(!j.isNumber);

    j = b;
    assert(j.isNumber);

    j = n;
    assert(j.isNumber);

    j = r;
    assert(j.isNumber);

    j = str;
    assert(!j.isNumber);

    j = arr;
    assert(!j.isNumber);

    j = obj;
    assert(!j.isNumber);
}

// Test isString
unittest {
    bool b = true;
    int n = 1;
    real r = 1.0;
    string str = "";
    JSON[] arr;
    JSON[string] obj;

    JSON j;
    assert(!j.isNumber);

    j = b;
    assert(!j.isString);

    j = n;
    assert(!j.isString);

    j = r;
    assert(!j.isString);

    j = str;
    assert(j.isString);

    j = arr;
    assert(!j.isString);

    j = obj;
    assert(!j.isString);
}

// Test isNull
unittest {
    bool b = true;
    int n = 1;
    real r = 1.0;
    string str = "";
    JSON[] arr;
    JSON[string] obj;

    JSON j;
    assert(j.isNull);

    j = b;
    assert(!j.isNull);

    j = n;
    assert(!j.isNull);

    j = r;
    assert(!j.isNull);

    j = str;
    assert(!j.isNull);

    j = arr;
    assert(!j.isNull);

    j = obj;
    assert(!j.isNull);
}

// Test isArray
unittest {
    bool b = true;
    int n = 1;
    real r = 1.0;
    string str = "";
    JSON[] arr;
    JSON[string] obj;

    JSON j;
    assert(!j.isArray);

    j = b;
    assert(!j.isArray);

    j = n;
    assert(!j.isArray);

    j = r;
    assert(!j.isArray);

    j = str;
    assert(!j.isArray);

    j = arr;
    assert(j.isArray);

    j = obj;
    assert(!j.isArray);
}

// Test isObject
unittest {
    bool b = true;
    int n = 1;
    real r = 1.0;
    string str = "";
    JSON[] arr;
    JSON[string] obj;

    JSON j;
    assert(!j.isObject);

    j = b;
    assert(!j.isObject);

    j = n;
    assert(!j.isObject);

    j = r;
    assert(!j.isObject);

    j = str;
    assert(!j.isObject);

    j = arr;
    assert(!j.isObject);

    j = obj;
    assert(j.isObject);
}

// Test jsonArray()
unittest {
    JSON arr = jsonArray();

    assert(arr.isArray);
    assert(arr.length == 0);
}

// Test array concatenate.
unittest {
    JSON j = jsonArray();

    JSON[] arr;
    JSON[string] obj;
    JSON otherJ = 3;

    j = j ~ null;
    j = j ~ true;
    j = j ~ 1u;
    j = j ~ 1;
    j = j ~ 1.0;
    j = j ~ "bla";
    j = j ~ arr;
    j = j ~ obj;
    j = j ~ otherJ;

    assert(j.array[0].isNull);
    assert(cast(bool) j.array[1] == true);
    assert(cast(int) j.array[3] == 1);
    assert(cast(real) j.array[4] == 1.0);
    assert(cast(string) j.array[5] == "bla");
    assert(j.array[6].array == []);
    assert(j.array[7].object.length == 0);
    assert(cast(int) j.array[8] == 3);
}

// Test array append.
unittest {
    JSON j = jsonArray();

    JSON[] arr;
    JSON[string] obj;
    JSON otherJ = 3;

    // It's important to use rvalues for these kinds of tests.
    // Otherwise, we might end up with broken code because the overloads
    // except references to lvalues.
    j ~= null;
    j ~= true;
    j ~= 1u;
    j ~= 1;
    j ~= 1.0;
    j ~= "bla";
    j ~= arr;
    j ~= obj;
    j ~= otherJ;

    assert(j.array[0].isNull);
    assert(cast(bool) j.array[1] == true);
    assert(cast(int) j.array[3] == 1);
    assert(cast(float) j.array[4] == 1.0);
    assert(cast(string) j.array[5] == "bla");
    assert(j.array[6].array == arr);
    assert(j.array[7].object == obj);
    assert(cast(int) j.array[8] == 3);
}

// Test array index get.
unittest {
    JSON j = jsonArray();

    bool b = true;
    int n = 1;
    real r = 1.0;
    string str = "bla";
    JSON[] arr;
    JSON[string] obj;
    JSON otherJ = 3;

    j.array ~= JSON(null);
    j.array ~= JSON(b);
    j.array ~= JSON(n);
    j.array ~= JSON(r);
    j.array ~= JSON(str);
    j.array ~= JSON(arr);
    j.array ~= JSON(obj);
    j.array ~= otherJ;

    assert(j[0].isNull);
    assert(cast(bool) j[1] == b);
    assert(cast(int) j[3] == n);
    assert(cast(real) j[3] == r);
    assert(cast(string) j[4] == str);
    assert(j[5].array == arr);
    assert(j[6].object == obj);
    assert(cast(int) j[7] == 3);
}

// Test array index set.
unittest {
    JSON j = jsonArray();

    JSON[] arr;
    JSON[string] obj;
    JSON otherJ = 3;

    j.length = 9;

    j[0] = null;
    j[1] = true;
    j[2] = 1u;
    j[3] = 1;
    j[4] = 1.0;
    j[5] = "bla";
    j[6] = arr;
    j[7] = obj;
    j[8] = otherJ;

    assert(j[0].isNull);
    assert(cast(bool) j[1] == true);
    assert(cast(int) j[3] == 1);
    assert(cast(real) j[4] == 1.0);
    assert(cast(string) j[5] == "bla");
    assert(j[6].array == arr);
    assert(j[7].object == obj);
    assert(cast(int) j[8] == 3);
}

// Test jsonObject()
unittest {
    JSON obj = jsonObject();

    assert(obj.isObject);
    assert(obj.length == 0);
}

// Test object key get.
unittest {
    bool b = true;
    int n = 1;
    real r = 1.0;
    string str = "bla";
    JSON[] arr;
    JSON[string] obj;
    JSON otherJ = 3;

    JSON[string] origObj;

    origObj["a"] = JSON(null);
    origObj["b"] = JSON(b);
    origObj["d"] = JSON(n);
    origObj["e"] = JSON(r);
    origObj["f"] = JSON(str);
    origObj["g"] = JSON(arr);
    origObj["h"] = JSON(obj);
    origObj["i"] = otherJ;

    JSON j = origObj;

    assert(j["a"].isNull);
    assert(cast(bool) j["b"] == b);
    assert(cast(int) j["d"] == n);
    assert(cast(real) j["e"] == r);
    assert(cast(string) j["f"] == str);
    assert(j["g"].array.length == 0);
    assert(j["h"].object.length == 0);
    assert(j["i"] == otherJ);
}

// Test object key set.
unittest {
    JSON[] arr;
    JSON[string] obj;
    JSON otherJ = 3;

    JSON j = jsonObject();

    j["a"] = null;
    j["b"] = true;
    j["c"] = 1u;
    j["d"] = 1;
    j["e"] = 1.0;
    j["f"] = "bla";
    j["g"] = arr;
    j["h"] = obj;
    j["i"] = otherJ;

    assert(j["a"].isNull);
    assert(cast(bool) j["b"] == true);
    assert(cast(int) j["d"] == 1);
    assert(cast(real) j["e"] == 1.0);
    assert(cast(string) j["f"] == "bla");
    assert(j["g"].array.length == 0);
    assert(j["h"].object.length == 0);
    assert(j["i"] == otherJ);
}

// Test "in" operator for object.
unittest {
    JSON obj = jsonObject();

    obj["a"] = 347;
    obj["b"] = true;
    obj["c"] = "beepbeep";
    obj["d"] = null;

    assert(cast(int) (*("a" in obj)) == 347);
    assert(cast(bool) (*("b" in obj)) == true);
    assert(cast(string) (*("c" in obj)) == "beepbeep");
    assert((*("d" in obj)).isNull);
}

// Test 'if' for various values
unittest {
    assert(!JSON(null));
    assert(!JSON(false));
    assert(JSON(true));
    assert(JSON(1u));
    assert(!JSON(0u));
    assert(JSON(-1));
    assert(!JSON(0));
    assert(JSON(1.0));
    assert(!JSON(0.0));
    assert(JSON("wat"));
    assert(!JSON(""));
    assert(!jsonArray());
    assert(!jsonObject());

    auto arr = jsonArray();
    arr.length = 1;

    assert(arr);

    auto obj = jsonObject();
    obj["a"] = 1;

    assert(obj);
}

// Test array value-only foreach for arrays.
unittest {
    JSON arr = jsonArray();

    arr ~= 347;
    arr ~= true;
    arr ~= "beepbeep";
    arr ~= null;

    int count = 0;

    foreach(val; arr) {
        final switch (count) {
        case 0:
            assert(cast(int) val == 347);
        break;
        case 1:
            assert(cast(bool) val == true);
        break;
        case 2:
            assert(cast(string) val == "beepbeep");
        break;
        case 3:
            assert(val.isNull);
        break;
        }

        ++count;
    }

    assert(count == 4);
}

// Test index-value foreach for arrays.
unittest {
    JSON arr = jsonArray();

    arr ~= 347;
    arr ~= true;
    arr ~= "beepbeep";
    arr ~= null;

    foreach(size_t index, val; arr) {
        final switch (index) {
        case 0:
            assert(cast(int) val == 347);
        break;
        case 1:
            assert(cast(bool) val == true);
        break;
        case 2:
            assert(cast(string) val == "beepbeep");
        break;
        case 3:
            assert(val.isNull);
        break;
        }
    }
}

// Test value-only foreach for objects.
unittest {
    JSON obj = jsonObject();

    obj["a"] = 347;
    obj["b"] = true;
    obj["c"] = "beepbeep";
    obj["d"] = null;

    int count = 0;

    foreach(val; obj) {
        if (val.isNumber) {
            assert(cast(bool) val == true);
        } else if(val.isString) {
            assert(cast(string) val == "beepbeep");
        } else {
            assert(val.isNull);
        }

        ++count;
    }

    assert(count == 4);
}

// Test key-value foreach for objects.
unittest {
    JSON obj = jsonObject();

    obj["a"] = 347;
    obj["b"] = true;
    obj["c"] = "beepbeep";
    obj["d"] = null;

    int count = 0;

    foreach(string key, val; obj) {
        final switch (key) {
        case "a":
            assert(cast(int) val == 347);
        break;
        case "b":
            assert(cast(bool) val == true);
        break;
        case "c":
            assert(cast(string) val == "beepbeep");
        break;
        case "d":
            assert(val.isNull);
        break;
        }

        ++count;
    }

    assert(count == 4);
}

// Test key-value foreach for arrays.
unittest {
    JSON arr = jsonArray();

    arr ~= 347;
    arr ~= true;
    arr ~= "beepbeep";
    arr ~= null;

    foreach(string key, val; arr) {
        final switch (key) {
        case "0":
            assert(cast(int) val == 347);
        break;
        case "1":
            assert(cast(bool) val == true);
        break;
        case "2":
            assert(cast(string) val == "beepbeep");
        break;
        case "3":
            assert(val.isNull);
        break;
        }
    }
}

// Test that index-value foreach for objects causes an exception.
unittest {
    JSON obj = jsonObject();

    bool failed = false;

    try {
        foreach(size_t index, val; obj) {}
    } catch (Exception ex) {
        failed = true;
    }

    assert(failed, "foreach (size_t index, val) did not throw "
    ~ "for an object!");
}

// Test array value-only foreach_reverse for arrays.
unittest {
    JSON arr = jsonArray();

    arr ~= 347;
    arr ~= true;
    arr ~= "beepbeep";
    arr ~= null;

    int count = 3;

    foreach_reverse(val; arr) {
        final switch (count) {
        case 0:
            assert(cast(int) val == 347);
        break;
        case 1:
            assert(cast(bool) val == true);
        break;
        case 2:
            assert(cast(string) val == "beepbeep");
        break;
        case 3:
            assert(val.isNull);
        break;
        }

        --count;
    }
}

// Test index-value foreach_reverse for arrays.
unittest {
    JSON arr = jsonArray();

    arr ~= 347;
    arr ~= true;
    arr ~= "beepbeep";
    arr ~= null;

    int count = 3;

    foreach_reverse(size_t index, val; arr) {
        assert(index == count--);

        final switch (index) {
        case 0:
            assert(cast(int) val == 347);
        break;
        case 1:
            assert(cast(bool) val == true);
        break;
        case 2:
            assert(cast(string) val == "beepbeep");
        break;
        case 3:
            assert(val.isNull);
        break;
        }
    }
}

// Test value-only foreach_reverse for objects.
unittest {
    JSON obj = jsonObject();

    obj["a"] = 347;
    obj["b"] = true;
    obj["c"] = "beepbeep";
    obj["d"] = null;

    int count = 0;

    foreach_reverse(val; obj) {
        if (val.isNumber) {
            assert(cast(bool) val == true);
        } else if(val.isString) {
            assert(cast(string) val == "beepbeep");
        } else {
            assert(val.isNull);
        }

        ++count;
    }

    assert(count == 4);
}

// Test key-value foreach_reverse for objects.
unittest {
    JSON obj = jsonObject();

    obj["a"] = 347;
    obj["b"] = true;
    obj["c"] = "beepbeep";
    obj["d"] = null;

    int count = 0;

    foreach_reverse(string key, val; obj) {
        final switch (key) {
        case "a":
            assert(cast(int) val == 347);
        break;
        case "b":
            assert(cast(bool) val == true);
        break;
        case "c":
            assert(cast(string) val == "beepbeep");
        break;
        case "d":
            assert(val.isNull);
        break;
        }

        ++count;
    }

    assert(count == 4);
}

// Test key-value foreach_reverse for arrays.
unittest {
    JSON arr = jsonArray();

    arr ~= 347;
    arr ~= true;
    arr ~= "beepbeep";
    arr ~= null;

    int count = 3;

    foreach_reverse(string key, val; arr) {
        assert(to!string(count--) == key);

        final switch (key) {
        case "0":
            assert(cast(int) val == 347);
        break;
        case "1":
            assert(cast(bool) val == true);
        break;
        case "2":
            assert(cast(string) val == "beepbeep");
        break;
        case "3":
            assert(val.isNull);
        break;
        }
    }
}

// Test that index-value foreach_reverse for objects causes an exception.
unittest {
    JSON obj = jsonObject();

    bool failed = false;

    try {
        foreach_reverse(size_t index, val; obj) {}
    } catch (Exception ex) {
        failed = true;
    }

    assert(failed, "foreach_reverse (size_t index, val) did not throw "
    ~ "for an object!");
}

// Test various uses of opEquals
unittest {
    string str = "string";
    JSON jstr = "string";

    assert(str == jstr);
    assert(jstr != [1, 2]);

    int integer = 34343;
    JSON jinteger = 34343;

    assert(jinteger == integer);
    assert(jinteger != [1, 2]);

    float floating = 2.5;
    JSON jfloating = 2.5;

    assert(floating == jfloating);
    assert(jfloating != "2.5");

    JSON arr = jsonArray();
    arr.length = 3;

    arr[0] = 123;
    arr[1] = 456;
    arr[2] = 789;

    assert(arr == [123, 456, 789]);

    JSON obj1 = jsonObject();

    obj1["a"] = "wat";
    obj1["b"] = 1;
    obj1["c"] = null;

    JSON obj2 = jsonObject();

    obj2["a"] = "wat";
    obj2["b"] = 1;
    obj2["c"] = null;

    assert(obj1 == obj2);
    assert(obj1 != arr);
}

// Test convertJSON with JSON itself.
unittest {
    JSON j;

    JSON x = convertJSON(j);
}

// Test convertJSON with primitives.
unittest {
    JSON a = convertJSON(3);
    JSON b = convertJSON("bee");
    JSON c = convertJSON(null);
    JSON d = convertJSON(4.5);

    assert(cast(int) a == 3);
    assert(cast(string) b == "bee");
    assert(c.isNull);
    assert(cast(real) d == 4.5);
}

// Test convertJSON with an array literal.
unittest {
    JSON j = convertJSON([
        [1, 2, 3],
        [4, 5, 6],
        [7, 8, 9]
    ]);

    assert(j.length == 3);
    assert(j[0].length == 3);
    assert(cast(int) j[0][0] == 1);
    assert(cast(int) j[0][1] == 2);
    assert(cast(int) j[0][2] == 3);
    assert(j[1].length == 3);
    assert(cast(int) j[1][0] == 4);
    assert(cast(int) j[1][1] == 5);
    assert(cast(int) j[1][2] == 6);
    assert(j[2].length == 3);
    assert(cast(int) j[2][0] == 7);
    assert(cast(int) j[2][1] == 8);
    assert(cast(int) j[2][2] == 9);
}

// Test convertJSON with an object literal.
unittest {
    JSON j = convertJSON([
        "a": [1, 2, 3],
        "b": [4, 5, 6],
        "c": [7, 8, 9]
    ]);

    assert(j.length == 3);
    assert("a" in j && j["a"].length == 3);
    assert(cast(int) j["a"][0] == 1);
    assert(cast(int) j["a"][1] == 2);
    assert(cast(int) j["a"][2] == 3);
    assert("b" in j && j["b"].length == 3);
    assert(cast(int) j["b"][0] == 4);
    assert(cast(int) j["b"][1] == 5);
    assert(cast(int) j["b"][2] == 6);
    assert("c" in j && j["c"].length == 3);
    assert(cast(int) j["c"][0] == 7);
    assert(cast(int) j["c"][1] == 8);
    assert(cast(int) j["c"][2] == 9);
}

// Test convertJSON with something invalid
unittest {
    static if(__traits(compiles, convertJSON([1 : [1, 2, 3]]))) {
        assert(false);
    }
}

// Test various kinds of output from toJSON with JSON types.
unittest {
    assert(toJSON(JSON("bla\\")) == `"bla\\"`);
    assert(toJSON(JSON(4.7)) == "4.7");
    assert(toJSON(JSON(12)) == "12");

    JSON j0 = convertJSON([
        "abc\"", "def", "djw\nw"
    ]);

    assert(toJSON(j0) == `["abc\"","def","djw\nw"]`);

    JSON j1 = convertJSON([
        "abc\"": 1234,
        "def": 5,
        "djw\nw": 1337
    ]);

    assert(toJSON(j1) == `{"abc\"":1234,"def":5,"djw\nw":1337}`);

    JSON j2 = convertJSON([
        "abc\"": ["bla", "bla", "bla"],
        "def": [],
        "djw\nw": ["beep", "boop"]
    ]);

    assert(toJSON(j2) == `{"abc\"":["bla","bla","bla"],`
        ~ `"def":[],"djw\nw":["beep","boop"]}`);
}

// Test parseJSON for keywords
unittest {
    assert(parseJSON(`null`).isNull);
    assert(parseJSON(`true`).type == JSON_TYPE.BOOL);
    assert(parseJSON(`true`));
    assert(parseJSON(`false`).type == JSON_TYPE.BOOL);
    assert(!parseJSON(`false`));
}

// Test parseJSON for various string inputs
unittest {
    assert(cast(string) parseJSON(`"foo"`) == "foo");
    assert(cast(string) parseJSON("\r\n  \t\"foo\" \t \n") == "foo");
    assert(cast(string) parseJSON(`"\r\n\"\t\f\b\/"`) == "\r\n\"\t\f\b/");
    assert(cast(string) parseJSON(`"\u0347"`) == "\u0347");
    assert(cast(string) parseJSON(`"\u7430"`) == "\u7430");
    assert(cast(string) parseJSON(`"\uabcd"`) == "\uabcd");
    assert(cast(string) parseJSON(`"\uABCD"`) == "\uABCD");
}

// Test parseJSON for various number inputs
unittest {
    assert(cast(int) parseJSON(`123`) == 123);
    assert(cast(int) parseJSON(`-340`) == -340);
    assert(approxEqual(cast(real) parseJSON(`9.53`), 9.53, 0.001));
    assert(cast(int) parseJSON(`-123E3`) == -123_000);
    assert(cast(int) parseJSON(`-123E+3`) == -123_000);
    assert(approxEqual(cast(double) parseJSON(`123E-3`), 123e-3, 0.001));
    assert(approxEqual(cast(double) parseJSON(`12345678910.12345678910`),
        12345678910.12345678910));
    assert(approxEqual(cast(double) parseJSON(`-12345678910.12345678910`),
        -12345678910.12345678910));
    assert(cast(int) parseJSON(`-0.`) == 0);
    // Make sure long is represented precisely.
    assert(cast(long) parseJSON(to!string(long.max)) == long.max);
}

// Test parseJSON for various arrays.
unittest {
    JSON arr1 = parseJSON(`  [1, 2, 3, 4, 5]` ~ "\n\t\r");

    assert(arr1.isArray);
    assert(arr1.length == 5);
    assert(cast(int) arr1[0] == 1);
    assert(cast(int) arr1[1] == 2);
    assert(cast(int) arr1[2] == 3);
    assert(cast(int) arr1[3] == 4);
    assert(cast(int) arr1[4] == 5);

    JSON arr2 = parseJSON("  [\"bla bla\",\n true, \r\n null, false]\n\t\r");

    assert(arr2.isArray);
    assert(arr2.length == 4);
    assert(cast(string) arr2[0] == "bla bla");
    assert(cast(bool) arr2[1] == true);
    assert(arr2[2].isNull);
    assert(cast(bool) arr2[3] == false);
}

// Test parseJSON for various objects.
unittest {
    JSON obj1 = parseJSON(`  {"a":1, "b" :  2, "c" : 3, "d" : 4}` ~ "\n\t\r");

    assert(obj1.isObject);
    assert(obj1.length == 4);
    assert(cast(int) obj1["a"] == 1);
    assert(cast(int) obj1["b"] == 2);
    assert(cast(int) obj1["c"] == 3);
    assert(cast(int) obj1["d"] == 4);

    JSON obj2 = parseJSON(`{
        "foo" : "bla de bla",
        "john" : "something else",
        "bar" : null,
        "jane" : 4.7
    }`);

    assert(obj2.isObject);
    assert(obj2.length == 4);
    assert(cast(string) obj2["foo"] == "bla de bla");
    assert(cast(string) obj2["john"] == "something else");
    assert(obj2["bar"].isNull);
    assert(approxEqual(cast(real) obj2["jane"], 4.7, 0.001));
}

// Test parseJSON on empty arrays and objects
unittest {
    assert(parseJSON(`[]`).length == 0);
    assert(parseJSON(`{}`).length == 0);
    assert(parseJSON(" [\t \n] ").length == 0);
    assert(parseJSON(" {\r\n } ").length == 0);
}

// Test complicated parseJSON examples
unittest {
    JSON obj = parseJSON(`{
        "array" : [1, 2, 3, 4, 5],
        "matrix" : [
            [ 1,  2,  3,  4,  5],
            [ 6,  7,  8,  9, 10],
            [11, 12, 13, 14, 15]
        ],
        "obj" : {
            "this" : 1,
            "is": 2,
            "enough": true
        }
    }`);

    assert(obj.isObject);
    assert(obj.length == 3);
    assert("array" in obj);

    JSON array = obj["array"];

    assert(array.isArray);
    assert(array.length == 5);
    assert(cast(int) array[0] == 1);
    assert(cast(int) array[1] == 2);
    assert(cast(int) array[2] == 3);
    assert(cast(int) array[3] == 4);
    assert(cast(int) array[4] == 5);

    assert("matrix" in obj);

    JSON matrix = obj["matrix"];

    assert(matrix.isArray);
    assert(matrix.length == 3);

    assert(matrix[0].isArray);
    assert(matrix[0].length == 5);
    assert(cast(int) matrix[0][0] == 1);
    assert(cast(int) matrix[0][1] == 2);
    assert(cast(int) matrix[0][2] == 3);
    assert(cast(int) matrix[0][3] == 4);
    assert(cast(int) matrix[0][4] == 5);
    assert(matrix[1].isArray);
    assert(matrix[1].length == 5);
    assert(cast(int) matrix[1][0] == 6);
    assert(cast(int) matrix[1][1] == 7);
    assert(cast(int) matrix[1][2] == 8);
    assert(cast(int) matrix[1][3] == 9);
    assert(cast(int) matrix[1][4] == 10);
    assert(matrix[2].isArray);
    assert(matrix[2].length == 5);
    assert(cast(int) matrix[2][0] == 11);
    assert(cast(int) matrix[2][1] == 12);
    assert(cast(int) matrix[2][2] == 13);
    assert(cast(int) matrix[2][3] == 14);
    assert(cast(int) matrix[2][4] == 15);

    assert("obj" in obj);

    JSON subObj = obj["obj"];

    assert(subObj.isObject);
    assert(subObj.length == 3);

    assert(cast(int) subObj["this"] == 1);
    assert(cast(int) subObj["is"] == 2);
    assert(cast(bool) subObj["enough"] == true);
}

// Test indented writing
unittest {
    JSON j = jsonArray();

    j ~= 3;
    j ~= "hello";
    j ~= 4.5;

    string result = toJSON!4(j);

    assert(result ==
`[
    3,
    "hello",
    4.5
]`);
}

// Test the toJSONArray function with ranges.
unittest {
    JSON j = [1, 2, 3].toJSONArray();

    assert(j.length == 3);
    assert(j[0] == 1);
    assert(j[1] == 2);
    assert(j[2] == 3);

    JSON j2 = [[1, 2], [3, 4]].toJSONArray();


    assert(j2.length == 2);

    assert(j2[0].length == 2);
    assert(j2[0][0] == 1);
    assert(j2[0][1] == 2);

    assert(j2[1].length == 2);
    assert(j2[1][0] == 3);
    assert(j2[1][1] == 4);
}

// Test opAssign.
unittest {
    JSON j;

    assert((j = 3) == 3);
}

// Test immutable
unittest {
    immutable JSON j1 = true;
    assert(j1 == true);

    immutable JSON j2 = 3;
    assert(j2 == 3);

    immutable JSON j3 = -33;
    assert(j3 == -33);

    immutable JSON j4 = 4.5;
    assert(j4 == 4.5);

    // FIXME: This fails.
    //immutable JSON j5 = "some text";
    //assert(j5 == "some text");
}
