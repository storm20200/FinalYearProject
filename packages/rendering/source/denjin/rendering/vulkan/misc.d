/**
    A collection of miscellaneous vulkan-related functionality.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.misc;

// Phobos.
import core.stdc.string : strcmp;
import std.conv         : to;
import std.exception    : enforce;
import std.traits       : isBuiltinType, isFunctionPointer, isPointer, Unqual;

// External.
import erupted.types :  uint32_t, VkExtensionProperties, VkLayerProperties, VkResult, VK_VERSION_MAJOR, 
                        VK_VERSION_MINOR, VK_VERSION_PATCH, VK_SUCCESS;

/// Throws an exception if the error code of a Vulkan function indicates failure.
/// Params: 
///     code = The Vulkan error code that was generated.
pure @safe
void enforceSuccess (in VkResult code)
{
    enforce (code == VK_SUCCESS, code.to!string);
}

/// Gets the correct null handle to use when checking if a VK handle is null.
/// Params: T = The type to retrieve the null handle for.
template nullHandle (T)
    if (isBuiltinType!T || isPointer!T)
{
    import erupted.types : VK_NULL_HANDLE, VK_NULL_ND_HANDLE;

    enum handle = T.init;
    static if (__traits (compiles, handle == VK_NULL_HANDLE))
    {
        enum nullHandle = VK_NULL_HANDLE;
    }

    else static if (__traits (compiles, handle == VK_NULL_ND_HANDLE))
    {
        enum nullHandle = VK_NULL_ND_HANDLE;
    }

    else
    {
        static assert (false);
    }
}

/// Checks if the given Vulkan handle needs destroying, if so then the given function pointer will be used to destroy
/// the object. A check will be performed to see if the given function pointer is valid, if it isn't valid an assertion
/// will occur.
/// Params:
///     handle      = The VK handle to be destroyed if necessary.
///     destoryFunc = The function to use to destroy the handle.
///     params      = Parameters to be passed to the destroy function.
auto safelyDestroyVK (Handle, Func, T...) (ref Handle handle, in Func destroyFunc, auto ref T params)
    if ((isBuiltinType!Handle || isPointer!Handle) && isFunctionPointer!Func)
{
    import std.functional   : forward;
    import std.traits       : ReturnType;

    // The handle may not need destroying.
    enum nullH = nullHandle!Handle;
    if (handle != nullH)
    {
        // We must ensure the function is valid to avoid null-pointer deferencing.
        if (destroyFunc)
        {
            // Ensure we set the handle to null.
            scope (exit) handle = nullH;
            return destroyFunc (forward!params);
        }
    }

    // Return a blank object if we didn't need or were unable to call the function.
    alias returnType = ReturnType!Func;
    static if (!is (returnType == void))
    {
        return returnType.init;
    }
}

/// Checks if the given c-style layer name exists in the given collection of properties.
bool extensionOrLayerExists (Container) (in const(char)* name, in ref Container propertyContainer)
{
    foreach (ref property; propertyContainer)
    {
        static if (is (Unqual!(typeof (property)) == VkLayerProperties))
        {
            enum accessor = property.stringof ~ ".layerName.ptr";
        }
        else static if (is (Unqual!(typeof (property)) == VkExtensionProperties))
        {
            enum accessor = property.stringof ~ ".extensionName.ptr";
        }
        else static assert (false);

        if (name.strcmp (mixin (accessor)) == 0) return true;
    }
    return false;
}

/// Returns a string representation of a packed Vulkan version number. The string will be separated using full stops.
pure nothrow
string vulkanVersionString (in uint32_t versionNumber)
{
    return  VK_VERSION_MAJOR (versionNumber).to!string ~ "." ~
            VK_VERSION_MINOR (versionNumber).to!string ~ "." ~
            VK_VERSION_PATCH (versionNumber).to!string;
}