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
- The `Reflector` subtype used to process it

(both as pointers). It also returns the result of the operation.
The `Reflector` you pass determines what happens with the data. In the case of binary serialization (and in most others), there's in fact a separate `Reflector` for "reading" vs "writing" (serialising vs. deserialising) the data.

For example, to serialise some data hierarchy to a binary buffer, you'd do:
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

If, say, you wanted to serialise to json instead, the only change to the code above would be to use a json reader/writer instead of the binary one.
There's a few Reflectors provided with this module out of the box: there's an example `JsonReader` & `JsonWriter`, as well as an `ImGuiWriter` (WIP, there's no `ImGuiReader`, since it doesn't really make sense, as we'll see). More will be added as time permits.


## Customising behaviour
The example above will go through the entire data hierarchy contained in the struct that you passed. There are many scenarios in which you'll only want to serialise certain attributes contained in your types, because some stuff may be runtime-only, or you only want to persist some stuff and compute the rest of it, or whatever else.

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
Also, side note (pun intended), `field` is the abbreviated form of the note, but if for some reason that name is used for something else in your app, you can also use the equivalent `reflector_field`.


## Data model evolution
Most data models evolve over time during development, attributes get added, removed, renamed, etc. Using the same mechanism that you used above just to tell the reflector what gets persisted, you can support all these changes as well, by following a very simple set of rules:
- As mentioned above, the main unbreakable rule is that the field ids must correspond to a given attribute and only that attribute. That's how the reflector identifies which piece of data in the data stream corresponds to that attribute. You can assign id numbers as you see fit (up to U16_MAX, 0 is reserved), the simplest strategy is to just start at 1 and increase from there. But once an attribute has been serialised using a certain id, it must continue using that id for the lifetime of said attribute.
- _When a new attribute gets added_ to the struct, you simply give it a new *previously unused* id number.
- _When an attribute gets renamed_, you do nothing. As long as the type of the attribute and its id doesnt change, you can name it however you like, and everything just works.
- _When moving attributes around_, again you do nothing, just ensure the same field note is also moved together with its attribute so the id associations remain unchanged.
- _When an attribute gets deleted_, you simply stop using its id. It's also important that no new attributes re-use that same id, so a simple convention is to comment out the attribute (and its note) to leave a track record for the future and indicate that said field id has already been "consumed" and should never be used again.
- Changing the type of an existing attribute would in this model be equivalent to "deleting" the attribute then "adding" it again, i.e. instead of changing its type in place you'd comment it out and add a new attribute (with the same or different name) with a new field id.

That's pretty much it. Following these rules will mean _any data you have ever saved will be readable by any future version of your code, and any older version of your code can read any data you save now or in the future_. When a reader encounters fields in the data stream it doesnt know anything about, it'll simply skip them, and when any fields it does expect are missing from the data stream, they'll simply be given their default initialisation value.
