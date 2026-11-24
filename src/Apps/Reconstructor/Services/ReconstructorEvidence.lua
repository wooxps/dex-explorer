--!strict

------------------------------ Module ------------------------------

local function Main()
	local Evidence = {}
	local function key(path)
		local parts = {}
		for _, name in ipairs(path) do
			parts[#parts + 1] = #name .. ":" .. name
		end
		return table.concat(parts)
	end
	Evidence.Key = key
	function Evidence.Create(limit)
		local self = { Roots = {}, Nodes = {}, Count = 0, Dropped = 0, Revision = 0 }
		function self:Add(path, evidence)
			local changed = false
			if path[1] ~= "ServerStorage" and path[1] ~= "ServerScriptService" then
				return
			end
			if #path > 64 then
				self.Dropped += 1
				return
			end
			local parent, prefix
			prefix = {}
			for depth, name in ipairs(path) do
				if type(name) ~= "string" or #name == 0 or #name > 512 then
					return
				end
				prefix[depth] = name
				local id = key(prefix)
				local node = self.Nodes[id]
				if not node then
					if self.Count >= (limit or 10000) then
						self.Dropped += 1
						return
					end
					node = {
						Id = id,
						Name = name,
						Path = table.clone(prefix),
						Parent = parent,
						Children = {},
						Evidence = {},
						EvidenceKeys = {},
						Classes = {},
						ClassScores = {},
						Occurrences = 0,
					}
					self.Nodes[id], self.Count = node, self.Count + 1
					changed = true
					if parent then
						parent.Children[#parent.Children + 1] = node
					else
						self.Roots[#self.Roots + 1] = node
					end
				end
				parent = node
			end
			if not parent or not evidence then
				if changed then
					self.Revision += 1
				end
				return parent
			end
			local identity = tostring(evidence.Source)
				.. ":"
				.. tostring(evidence.Line)
				.. ":"
				.. tostring(evidence.Kind)
				.. ":"
				.. tostring(evidence.Class)
			if not parent.EvidenceKeys[identity] then
				changed = true
				parent.EvidenceKeys[identity] = true
				parent.Occurrences += 1
				if #parent.Evidence < 12 then
					parent.Evidence[#parent.Evidence + 1] = evidence
				end
			end
			if evidence.Class and not parent.Classes[evidence.Class] then
				parent.Classes[evidence.Class] = true
				changed = true
			end
			if evidence.Class then
				local score = evidence.Kind == "error-reported container class" and 3
					or (evidence.Kind == "require target" or evidence.Kind == "bytecode require target") and 2
					or 1
				if score > (parent.ClassScores[evidence.Class] or 0) then
					parent.ClassScores[evidence.Class] = score
					changed = true
				end
			end
			if changed then
				self.Revision += 1
			end
			return parent
		end
		function self:ClassLabel(node)
			if #node.Path == 1 then
				return node.Name
			end
			local classes = {}
			for class in pairs(node.Classes) do
				classes[#classes + 1] = class
			end
			table.sort(classes)
			return #classes == 0 and "Unknown" or table.concat(classes, " / ") .. "?"
		end
		function self:ResolveClass(node)
			local best, score, conflict = nil, 0, false
			for class, weight in pairs(node.ClassScores) do
				if weight > score then
					best, score, conflict = class, weight, false
				elseif weight == score then
					conflict = true
				end
			end
			if best and not conflict then
				return best, score == 3 and "Error-reported" or "Inferred"
			end
			return "Folder", conflict and "Conflicting class hints; Folder fallback" or "Unknown class; Folder fallback"
		end
		function self:Export()
			local rows = {}
			for _, node in pairs(self.Nodes) do
				rows[#rows + 1] = {
					Path = node.Path,
					ClassHint = self:ClassLabel(node),
					Evidence = node.Evidence,
					ModuleMembers = node.ModuleMembers,
					Occurrences = node.Occurrences,
				}
			end
			table.sort(rows, function(a, b)
				return key(a.Path) < key(b.Path)
			end)
			return { Schema = 1, Inferred = true, Complete = false, Nodes = rows, Dropped = self.Dropped }
		end
		self:Add({ "ServerStorage" })
		self:Add({ "ServerScriptService" })
		return self
	end
	return Evidence
end
return { Main = Main }
