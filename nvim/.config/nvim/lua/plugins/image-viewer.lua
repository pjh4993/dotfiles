-- External image preview via macOS Quick Look / Preview.app
-- Works in any terminal (WaveTerm has no kitty graphics protocol, so
-- snacks.image can't render inline there).
-- <leader>ci opens the current image buffer, or the image path under cursor.
local image_exts = { png = true, jpg = true, jpeg = true, gif = true, webp = true, bmp = true, svg = true, ico = true, tiff = true, heic = true }

local function is_image(path)
  local ext = path:match("%.(%w+)$")
  return ext ~= nil and image_exts[ext:lower()] == true
end

local function image_preview()
  -- Current buffer is an image → open it
  local bufpath = vim.fn.expand("%:p")
  if is_image(bufpath) and vim.fn.filereadable(bufpath) == 1 then
    vim.fn.jobstart({ "open", bufpath })
    return
  end

  -- Otherwise try the path under the cursor (e.g. markdown image link)
  local cfile = vim.fn.expand("<cfile>")
  if cfile == "" or not is_image(cfile) then
    vim.notify("No image file here or under cursor", vim.log.levels.WARN)
    return
  end

  -- Resolve relative paths against the buffer's directory
  local path = cfile
  if not path:match("^[/~]") and not path:match("^%a+://") then
    path = vim.fn.expand("%:p:h") .. "/" .. cfile
  end
  path = vim.fn.expand(path)

  if path:match("^%a+://") or vim.fn.filereadable(path) == 1 then
    vim.fn.jobstart({ "open", path })
  else
    vim.notify("Image not found: " .. path, vim.log.levels.WARN)
  end
end

vim.keymap.set("n", "<leader>ci", image_preview, { desc = "Image Preview (external)" })

return {}
