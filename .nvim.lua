
-- Set 'compiler' globally (could additionally have a different local setting for certain filetypes)
vim.cmd('compiler! jai')
-- Append some stuff to default makeprg options
-- TODO Test
vim.opt.makeprg:append(' -import_dir ' .. vim.env.DEV_HOME .. '/bin/jai_modules -')

-- For some reason using just ':p' is not showing the correct filename
print('Loaded ' .. vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":p:h") .. '\\.nvim.lua')
