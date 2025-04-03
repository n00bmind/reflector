# reflector
Reflection & serialization library for Jai

Some features:
- Fast binary serialization of arbitrary types
- Immune to data format evolution (stored data is forwards _and_ backwards compatible)
- Variety of reflectors for different purposes, all using the same "version immune" mechanism
- Easy to write your own custom reflectors

## Usage
There is pretty much a single procedure you need to get familiar with, called `Reflect`. It takes two arguments:
- The data you want to process
- The Reflector subtype used to process it
(both as pointers). The Reflector you pass determines what happens with the data. In the case of binary serialization (and in most others), there's in fact a separate Reflector for "reading" vs "writing" (serializing vs. deserializing) the data.

For example, to serialize some data hierarchy, you'd do:
```jai
    myDataStruct: MyStructType;
    // .. add stuff to it ...

    writer: BinaryWriter;
    writeResult := Reflect( *myDataStruct, *writer );
```
The BinaryWriter produces a byte buffer with the results, which you can write to disk or do whatever with. Then to reconstruct your data back from a byte buffer you'd do:
```jai
    reader: BinaryReader;
    reader.buffer = ...  // Point to your byte array

    myNewDataStruct: MyStructType;
    readResult := Reflect( *myNewDataStruct, *reader );
```
and that's it!
