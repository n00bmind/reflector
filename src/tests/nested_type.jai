
SimpleType :: struct
{
    num: s32;
}

ComplexType :: struct
{
    simple: SimpleType;
    nums: [] s32;
    str: string;
}

DeepType :: struct
{
    complex: ComplexType;
    n: s32;
}

DeeperType :: struct
{
    deep: DeepType;
    someText: string;
}

ChunkyType :: struct
{
    deeper: [..] DeeperType;
}

