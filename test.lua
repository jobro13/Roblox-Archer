local Tree = {}

function Tree:AddNode(Node)
	self[Node] = {}
end 

function Tree:AddToNode(Node, Data)
	self[Node] = Data 
end 

function Tree:FlushTree()
	for i,v in ipairs(self) do 
		self[i] = nil 
	end 
end 

function Tree:MakeNodes(Nodes, DataPerNode, PPCount)
	print("Making " .. Nodes .. " Nodes with " .. DataPerNode .. " data per node, total: " .. DataPerNode * Nodes)
	local DNow = collectgarbage("count")
	
	print("Memusage is now : " .. DNow .. "kb")
	local Counter = 0
	local Total = 0
	for Node = 1, Nodes do 
		local MyNode = {x = Node/Nodes, y = Node/Nodes, z = Node/Nodes}
		self:AddNode(MyNode)
		for Data = 1, DataPerNode do 
			self:AddToNode(MyNode, {})
			Counter = Counter + 1
			Total = Total + 1
			if Counter > (PPCount or math.huge) then 
				local progress = Total / (Nodes * DataPerNode) * 100
				print(progress .. "%")
				Counter = 0
			end
		end 
	end 

	local DNowLater = collectgarbage("count")
	print("Memusage @end: " .. DNowLater .. "kb , diff: " .. DNowLater - DNow)
	local Diff = DNowLater - DNow 
	local Nodes = DataPerNode * Nodes 
	--print(Diff/Nodes * 1000 .. " bytes per inst?")
end 

Tree:MakeNodes(100000,10000, 1000000)