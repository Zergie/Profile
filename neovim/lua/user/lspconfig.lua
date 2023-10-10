-- LSP settings.
--  This function gets run when an LSP connects to a particular buffer.
On_attach = function(client, bufnr)
  local nvim_create_autocmd = vim.api.nvim_create_autocmd
  local nmap = function(keys, func, desc)
    if desc then
      desc = 'LSP: ' .. desc
    end

    vim.keymap.set('n', keys, func, { buffer = bufnr, desc = desc })
  end
  local imap = function(keys, func, desc)
    if desc then
      desc = 'LSP: ' .. desc
    end

    vim.keymap.set('i', keys, func, { buffer = bufnr, desc = desc })
  end

  if client.name == "omnisharp" then
    client.server_capabilities.semanticTokensProvider = {
      full = vim.empty_dict(),
      legend = {
        tokenModifiers = { "static_symbol" },
        tokenTypes = { "comment", "excluded_code", "identifier", "keyword", "keyword_control", "number", "operator", "operator_overloaded", "preprocessor_keyword", "string", "whitespace", "text", "static_symbol", "preprocessor_text", "punctuation", "string_verbatim", "string_escape_character", "class_name", "delegate_name", "enum_name", "interface_name", "module_name", "struct_name", "type_parameter_name", "field_name", "enum_member_name", "constant_name", "local_name", "parameter_name", "method_name", "extension_method_name", "property_name", "event_name", "namespace_name", "label_name", "xml_doc_comment_attribute_name", "xml_doc_comment_attribute_quotes", "xml_doc_comment_attribute_value", "xml_doc_comment_cdata_section", "xml_doc_comment_comment", "xml_doc_comment_delimiter", "xml_doc_comment_entity_reference", "xml_doc_comment_name", "xml_doc_comment_processing_instruction", "xml_doc_comment_text", "xml_literal_attribute_name", "xml_literal_attribute_quotes", "xml_literal_attribute_value", "xml_literal_cdata_section", "xml_literal_comment", "xml_literal_delimiter", "xml_literal_embedded_expression", "xml_literal_entity_reference", "xml_literal_name", "xml_literal_processing_instruction", "xml_literal_text", "regex_comment", "regex_character_class", "regex_anchor", "regex_quantifier", "regex_grouping", "regex_alternation", "regex_text", "regex_self_escaped_character", "regex_other_escape", },
      },
      range = true,
    }
  end

  nmap("<Leader>e", vim.diagnostic.open_float, "Open diagnostics")
  nmap("[d", vim.diagnostic.goto_prev, "Prev diagnostics")
  nmap("]d", vim.diagnostic.goto_next, "Next diagnostics")
  nmap("<Leader>q", vim.diagnostic.setloclist, "setloclist")

  nmap('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
  nmap('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction')

  nmap('gd', vim.lsp.buf.definition, '[G]oto [D]efinition')
  nmap('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')
  nmap('gI', vim.lsp.buf.implementation, '[G]oto [I]mplementation')
  nmap('<leader>D', vim.lsp.buf.type_definition, 'Type [D]efinition')
  nmap('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')
  nmap('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')

  -- See `:help K` for why this keymap
  nmap('K', vim.lsp.buf.hover, 'Hover Documentation')
  nmap('<leader>K', vim.lsp.buf.signature_help, 'Signature Documentation')
  imap('<C-k>', vim.lsp.buf.signature_help, 'Signature Documentation')

  vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(
    vim.lsp.handlers.signature_help, {
        silent = true,
        focusable = false
    }
  )

  nvim_create_autocmd({"CursorHoldI"}, {
      pattern = "*.cs,*.ps1,*.py,*.ino",
      command = "lua vim.lsp.buf.signature_help()"
  })

  -- Lesser used LSP functionality
  nmap('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
  nmap('<leader>aa', vim.lsp.buf.add_workspace_folder, '[W]orkspace [A]dd Folder')
  nmap('<leader>ar', vim.lsp.buf.remove_workspace_folder, '[W]orkspace [R]emove Folder')
  nmap('<leader>al', function() print(vim.inspect(vim.lsp.buf.list_workspace_folders())) end, '[W]orkspace [L]ist Folders')

  -- Create a command `:Format` local to the LSP buffer
  vim.api.nvim_buf_create_user_command(bufnr, 'Format', function(_)
    vim.lsp.buf.format()
  end, { desc = 'Format current buffer with LSP' })
end
