# reflector
Reflection & serialisation library for Jai

Some features:
- Fast binary serialisation of arbitrary types
- Immune to data format evolution (stored data is forwards _and_ backwards compatible)
- Variety of reflectors for different purposes, all using the same "version immune" mechanism
- Easy to write your own custom reflectors

## Usage
There is pretty much a single procedure you need to get familiar with, called `Reflect`. It takes two arguments:
- The data you want to process
- The Reflector subtype used to process it
(both as pointers). It also returns the result of the operation.
The Reflector you pass determines what happens with the data. In the case of binary serialization (and in most others), there's in fact a separate Reflector for "reading" vs "writing" (serialising vs. deserialising) the data.

For example, to serialise some data hierarchy, you'd do:
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

There's a few Reflectors provided with this module. For example, there's an example `JsonReader` & `JsonWriter`, as well as an `ImGuiWriter` (WIP). There's no `ImGuiReader`, since it doesn't really make sense, as we'll see.


## Customising behaviour
Now the above code will go through the entire data hierarchy contained in the struct that you passed. There are many scenarios in which you'll only want to serialise certain attributes contained in your types, because some stuff may be runtime-only, or you only want to persist some stuff and compute the rest of it, or whatever else.

In that case, you'll need to annotate your type's attributes to indicate which ones should be "reflected" (i.e. processed) and which ones shouldn't, and you do that by attaching a `field` note next to the reflected attributes, like this:
```jai
Monster :: struct
{
    pos: Vec3;                  @field(1)
    mana: s16 = 150;            @field(2)
    hp: s16 = 100;
    friendly: bool = false;     @field(3)
    name: string = "Bob";       @field(4)
    inventory: [..] u8;
    color: Color = .Blue;       @field(5)
    weapons: [..] Weapon;       @field(6)
    path: [..] Vec3;
}
```
Now only attributes that have the note will be part of the persisted data. Note that these `field` notes also specify a very important "argument", which is their numeric **field id**. This ties in with the "version immunity" feature, as we'll explain later. The main thing you need to always keep in mind is _**field ids MUST correspond 1-to-1 with reflected attributes in a given type**_. This means you cannot have a repeated field id inside any given struct, and once you associate an id with a struct's attribute it must never change (you can use the same ids for attributes of different structs).
Also, side note, `field` is the abbreviated form of the note, but if for some reason that name is used for something else in your app, you can also use the equivalent `reflector_field`.
