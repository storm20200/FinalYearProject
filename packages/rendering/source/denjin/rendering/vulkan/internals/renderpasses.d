/**
    Contains different "render pass" structures which describe the framebuffer and sub-pass requirements of different
    rendering techniques including forward rendering and deferred shading.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.vulkan.internals.renderpasses;

// Phobos.
import std.typecons : Flag, Yes, No;

// Engine.
import denjin.rendering.vulkan.device       : Device;
import denjin.rendering.vulkan.misc         : enforceSuccess, safelyDestroyVK;
import denjin.rendering.vulkan.nulls        : nullDevice, nullPass, nullSwapchain;
import denjin.rendering.vulkan.objects      : createRenderPass;
import denjin.rendering.vulkan.swapchain    : Swapchain;

// External.
import erupted.types : VkAllocationCallbacks, VkAttachmentDescription, VkAttachmentReference, VkFormat, VkRenderPass, 
                       VkRenderPassCreateInfo, VkSubpassDependency, VkSubpassDescription,
                       VK_ATTACHMENT_LOAD_OP_CLEAR, VK_ATTACHMENT_LOAD_OP_DONT_CARE, VK_ATTACHMENT_LOAD_OP_LOAD, 
                       VK_ATTACHMENT_STORE_OP_STORE, VK_ATTACHMENT_STORE_OP_DONT_CARE, VK_FORMAT_D24_UNORM_S8_UINT,
                       VK_FORMAT_UNDEFINED, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                       VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, 
                       VK_PIPELINE_BIND_POINT_GRAPHICS, VK_SAMPLE_COUNT_1_BIT;

/// Initially contains a description of how a forward rendering pass works in the renderer, future enhancements would
/// enable support for deferred shading and deferred lighting.
struct RenderPasses
{
    VkRenderPass forward = nullPass; /// A dedicated forward render pass.

    public void create (ref Device device, in VkFormat colourFormat, in VkAllocationCallbacks* callbacks = null)
    in
    {
        assert (device != nullDevice);
        assert (forward == nullPass);
    }
    out
    {
        assert (forward != nullPass);
    }
    body
    {
        forward = DedicatedForwardRender.create (device, colourFormat);
    }

    public void clear (ref Device device, in VkAllocationCallbacks* callbacks = null) nothrow @nogc
    in
    {
        assert (device != nullDevice);
    }
    out
    {
        assert (forward == nullPass);
    }
    body
    {
        forward.safelyDestroyVK (device.vkDestroyRenderPass, device, forward, callbacks);
    }
}

/// Contains necessary attachment descriptions to build a forward rendering pass.
struct ForwardRender (Flag!"loadColour" loadColour, Flag!"storeColour" storeColour,
                      Flag!"loadDepth" loadDepth, Flag!"storeDepth" storeDepth,
                      Flag!"presentAfterUse" presentAfterUse)
{
    public enum VkAttachmentDescription colour = 
    {
        flags:          0,
        format:         VK_FORMAT_UNDEFINED,
        samples:        VK_SAMPLE_COUNT_1_BIT,
        loadOp:         loadColour ? VK_ATTACHMENT_LOAD_OP_LOAD : 
                        storeColour ? VK_ATTACHMENT_LOAD_OP_CLEAR : VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        storeOp:        storeColour ? VK_ATTACHMENT_STORE_OP_STORE : VK_ATTACHMENT_STORE_OP_DONT_CARE,
        stencilLoadOp:  VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
        initialLayout:  VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        finalLayout:    presentAfterUse ? VK_IMAGE_LAYOUT_PRESENT_SRC_KHR : VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
    };

    public enum VkAttachmentDescription depthStencil =
    {
        flags:          0,
        format:         VK_FORMAT_D24_UNORM_S8_UINT,
        samples:        VK_SAMPLE_COUNT_1_BIT,
        loadOp:         loadDepth ? VK_ATTACHMENT_LOAD_OP_LOAD : 
                        storeDepth ? VK_ATTACHMENT_LOAD_OP_CLEAR : VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        storeOp:        storeDepth ? VK_ATTACHMENT_STORE_OP_STORE : VK_ATTACHMENT_STORE_OP_DONT_CARE,
        stencilLoadOp:  VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
        initialLayout:  VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        finalLayout:    VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
    };

    /// Creates a forward rendering render pass with the templated colour and depth attachment parameters.
    public static VkRenderPass create (ref Device device, in VkFormat colourFormat, 
                                       in VkAllocationCallbacks* callbacks = null)
    {
        // We must update the format of the colour attachment based on the given swapchain.
        VkAttachmentDescription[2] attachmentDescriptions = [colour, depthStencil];
        attachmentDescriptions[0].format = colourFormat;

        // Create references to each attachment.
        VkAttachmentReference[attachmentDescriptions.length] references;
        foreach (i, ref r; references)
        {
            r.attachment    = i;
            r.layout        = attachmentDescriptions[i].initialLayout;
        }
    
        VkSubpassDescription[1] subpasses = 
        {
            flags:                      0,
            pipelineBindPoint:          VK_PIPELINE_BIND_POINT_GRAPHICS,
            inputAttachmentCount:       0,
            pInputAttachments:          null,
            colorAttachmentCount:       loadColour || storeColour ? 1 : 0,
            pColorAttachments:          loadColour || storeColour ? &references[0] : null,
            pResolveAttachments:        null,
            pDepthStencilAttachment:    loadDepth || storeDepth ? &references[1] : null,
            preserveAttachmentCount:    0,
            pPreserveAttachments:       null
        };
        VkSubpassDependency[0] dependencies;
        VkRenderPass handle = void;
        handle.createRenderPass (device, attachmentDescriptions[], subpasses[], dependencies[], callbacks).enforceSuccess;
        return handle;
    }
}

/// This forward render pass will have the driver automatically transition the colour attachment so it can be displayed
/// by the presentation engine when the rendering pass ends.
alias DedicatedForwardRender = ForwardRender!(No.loadColour, Yes.storeColour, No.loadDepth, No.storeDepth, Yes.presentAfterUse);

/// This forward render pass can be used to perform shadow mapping as no data is loaded but the depth value will be
/// stored.
alias DepthPass = ForwardRender!(No.loadColour, No.storeColour, No.loadDepth, Yes.storeDepth, No.presentAfterUse);