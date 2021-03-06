/**
    Contains functionality related to framebuffers used by the renderer. Consider merging this module with
    denjin.rendering.vulkan.internals.renderpasses as they seem to be tightly coupled.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: Copyright © 2017, Simon Peter Campbell
    License: MIT
*/
module denjin.rendering.vulkan.internals.framebuffers;

// Phobos.
import std.algorithm    : each;
import std.exception    : enforce;

// Engine.
import denjin.rendering.vulkan.device                   : Device;
import denjin.rendering.vulkan.internals.renderpasses   : RenderPasses;
import denjin.rendering.vulkan.misc                     : enforceSuccess, memoryTypeIndex, safelyDestroyVK;
import denjin.rendering.vulkan.nulls                    : nullDevice, nullFramebuffer, nullImage, nullImageView, 
                                                          nullMemory, nullSwapchain;
import denjin.rendering.vulkan.swapchain                : Swapchain;

// External.
import erupted.types : uint32_t, VkAllocationCallbacks, VkDeviceMemory, VkExtent3D, VkFramebuffer, 
                       VkFramebufferCreateInfo, VkImage, VkImageCreateInfo, VkImageView, VkImageViewCreateInfo, 
                       VkMemoryAllocateInfo, VkMemoryRequirements, VkPhysicalDeviceMemoryProperties, 
                       VK_COMPONENT_SWIZZLE_IDENTITY, VK_FORMAT_D24_UNORM_S8_UINT, VK_IMAGE_ASPECT_DEPTH_BIT, 
                       VK_IMAGE_ASPECT_STENCIL_BIT, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_TILING_OPTIMAL, 
                       VK_IMAGE_TYPE_2D, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT, VK_IMAGE_VIEW_TYPE_2D, 
                       VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, VK_SAMPLE_COUNT_1_BIT, VK_SHARING_MODE_EXCLUSIVE, 
                       VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO, VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, 
                       VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;

/**
    Contains images, image views and framebuffers which are used for different render passes by the renderer. Swapchain
    images are excluded from this as they are managed by the Swapchain. 
*/
struct Framebuffers
{
    VkFramebuffer[] framebuffers;                       /// A framebuffer for each swapchain image will be contained here.
    VkImageView     depthView       = nullImageView;    /// An attachable "view" of the actual depth buffer image.
    VkImage         depthImage      = nullImage;        /// A handle to the image being used as a depth buffer.
    VkDeviceMemory  depthMemory     = nullMemory;       /// A handle to the memory allocated to the depth buffer image.

    /// The extents need to be changed at run-time, otherwise this contains values necessary to create a depth buffer.
    enum VkImageCreateInfo depthImageInfo =
    {
        sType:                  VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        pNext:                  null,
        flags:                  0,
        imageType:              VK_IMAGE_TYPE_2D,
        format:                 VK_FORMAT_D24_UNORM_S8_UINT,
        extent:                 VkExtent3D (1, 1, 1),
        mipLevels:              1,
        arrayLayers:            1,
        samples:                VK_SAMPLE_COUNT_1_BIT,
        tiling:                 VK_IMAGE_TILING_OPTIMAL,
        usage:                  VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
        sharingMode:            VK_SHARING_MODE_EXCLUSIVE,
        queueFamilyIndexCount:  0,
        pQueueFamilyIndices:    null,
        initialLayout:          VK_IMAGE_LAYOUT_UNDEFINED
    };

    /// Retrieve the framebuffer at the given index.
    public inout(VkFramebuffer) framebuffer (in size_t index) inout pure nothrow @safe @nogc
    in
    {
        assert (index < framebuffers.length);
    }
    body
    {
        return framebuffers[index];
    }

    /// Creates the required framebuffers and images to provide the renderer with render targets.
    public void create (ref Device device, ref Swapchain swapchain, ref RenderPasses renderPasses,
                        in ref VkPhysicalDeviceMemoryProperties memProps, in VkAllocationCallbacks* callbacks = null)
    in
    {
        assert (device != nullDevice);
        assert (swapchain != nullSwapchain);
        assert (depthImage == nullImage);
        assert (depthView == nullImageView);
        assert (depthMemory == nullMemory);
    }
    out
    {
        assert (depthImage != nullImage);
        assert (depthView != nullImageView);
        assert (depthMemory != nullMemory);
    }
    body
    {
        createDepthBuffer (device, swapchain, memProps, callbacks);
        createFramebuffers (device, swapchain, renderPasses, callbacks);
    }

    /// Deletes stored resources and returns the object to an uninitialised state.
    public void clear (ref Device device, in VkAllocationCallbacks* callbacks = null) nothrow @nogc
    {
        framebuffers.each!((ref fb) => fb.safelyDestroyVK (device.vkDestroyFramebuffer, device, fb, callbacks));
        depthMemory.safelyDestroyVK (device.vkFreeMemory, device, depthMemory, callbacks);
        depthView.safelyDestroyVK (device.vkDestroyImageView, device, depthView, callbacks);
        depthImage.safelyDestroyVK (device.vkDestroyImage, device, depthImage, callbacks);
    }

    /// Creates a depth buffer for use with swapchain images when rendering into generated framebuffers.
    private void createDepthBuffer (ref Device device, in ref Swapchain swapchain, 
                                    in ref VkPhysicalDeviceMemoryProperties memProps,
                                    in VkAllocationCallbacks* callbacks = null)
    {
        // We need to update the size of the depth buffer.
        immutable displaySize   = swapchain.info.imageExtent;
        auto imageInfo          = depthImageInfo;
        imageInfo.extent        = VkExtent3D (displaySize.width, displaySize.height, 1);

        device.vkCreateImage (&imageInfo, callbacks, &depthImage).enforceSuccess;
        scope (failure) device.vkDestroyImage (depthImage, callbacks);
        
        // Allocate memory for the depth buffer.
        VkMemoryRequirements memory = void;
        device.vkGetImageMemoryRequirements (depthImage, &memory);
        
        VkMemoryAllocateInfo allocInfo = 
        {
            sType:              VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            pNext:              null,
            allocationSize:     memory.size,
            memoryTypeIndex:    memProps.memoryTypeIndex (memory.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
        };

        enforce (allocInfo.memoryTypeIndex != uint32_t.max);
        device.vkAllocateMemory (&allocInfo, callbacks, &depthMemory).enforceSuccess;
        scope (failure) device.vkFreeMemory (depthMemory, callbacks);

        // Bind the memory to the image.
        device.vkBindImageMemory (depthImage, depthMemory, 0).enforceSuccess;

        // Finally create the image view.
        VkImageViewCreateInfo viewInfo =
        {
            sType:          VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            pNext:          null,
            flags:          0,
            image:          depthImage,
            viewType:       VK_IMAGE_VIEW_TYPE_2D,
            format:         imageInfo.format,
            components:
            {
                r: VK_COMPONENT_SWIZZLE_IDENTITY, g: VK_COMPONENT_SWIZZLE_IDENTITY, 
                b: VK_COMPONENT_SWIZZLE_IDENTITY, a: VK_COMPONENT_SWIZZLE_IDENTITY
            },
            subresourceRange:
            {
                aspectMask:     VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT,
                baseMipLevel:   0,
                levelCount:     1,
                baseArrayLayer: 0,
                layerCount:     1
            }
        };
        device.vkCreateImageView (&viewInfo, callbacks, &depthView).enforceSuccess;
        scope (failure) device.vkDestroyImageView (depthView, callbacks);
    }

    /**
        Constructs a framebuffer for each image in the given swapchain.

        Created framebuffers will contain two attachments, the first will be a swapchain image and the second will be
        the member depth buffer. A framebuffer will be created for each image in the swapchain.
    */
    private void createFramebuffers (ref Device device, ref Swapchain swapchain, ref RenderPasses renderPasses,
                                     in VkAllocationCallbacks* callbacks)
    {
        // Start by setting the create info values which are common across all framebuffers.
        VkFramebufferCreateInfo info =
        {
            sType:              VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            pNext:              null,
            flags:              0,
            renderPass:         renderPasses.forward,
            attachmentCount:    2,
            pAttachments:       null,
            width:              swapchain.info.imageExtent.width,
            height:             swapchain.info.imageExtent.height,
            layers:             1
        };

        // We need to create a framebuffer for each image in the swapchain. This is because you can't change
        // attachments after a framebuffer has been created.
        framebuffers.length = swapchain.imageCount;
        foreach (i, ref fb; framebuffers)
        {
            const VkImageView[2] attachments = [swapchain.getImageView (i), depthView];
            info.pAttachments = attachments.ptr;

            device.vkCreateFramebuffer (&info, callbacks, &fb).enforceSuccess;
        }
    }
}