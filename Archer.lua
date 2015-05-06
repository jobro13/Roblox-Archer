local Archer = {}

-- Archer range. Archer will not work for ranged checks which are bigger than Range.
-- [note] It will not error, but it will miss targets.
Archer.Range = 20
Archer.JobTimer = 250 -- After x iterations, wait()
Archer.Iterations = 0

Archer.Mode = "PerInstance" -- Either "PerInstance" or "PerJob". 

-- Per Instance: :StartThread() will loop over all instances, then calling all jobs
-- Per Job: :StartThread() will loop over all jobs, then calling all instances

-- Instinct auto-calls this;
function Archer:Constructor()
	self.Tree = {} 
	self.Jobs = {}
end

function Archer:New()
	local my = setmetatable({}, {__index=self})
	my:Constructor()
	return my
end 

-- PUBLIC functions --

-- Add job;
-- Job should consist of the fields (METHODS)
-- ShouldRun(target) -> returns bool if the job should be worked for this target.
-- Parse (target, origin, range) -> parse for target, origin (the 'target' passed to ShouldRun) and the magnitude between positions of target and origin
-- Parse will not be called on itself. Use below functions to do such thing:
-- ParseSelfFirst(target) [optional] -> Parse the job for this target, before parsing for other targets. 
-- ParseSelfLast(target) [optional] -> Parse the job for this target, after parsing the other targets

-- Additionally, a Range parameter can be set. If this is not set, job will check for self.Range

-- Additionally, all Parse functions may return a 'weight' for the job done. this will be added towards the Iterations
-- If the iterations > jobtimer, the thread will yield.
function Archer:AddJob(Job)
	if Job.ShouldRun and Job.Parse then 
		table.insert(self.Jobs, Job)
	else 
		error("Cannot add this job. ShouldRun and Parse are not set.")
	end 
end 

-- Adds an Instance to the tree. Can be a model or basepart.
function Archer:Add(Inst)
	local Pos = self:GetPosition(Inst)
	local PosIdent = self:GetNode(Pos)
	self:Insert(Inst, PosIdent)
end 

function Archer:StartThread()
	assert(coroutine.resume(coroutine.create(function()
		if self.Mode == "PerJob" then 
			while wait(1/10) do 
				for _, Job in pairs(self.Jobs) do 
					self:DoJob(Job)
				end 
			end
		elseif self.Mode == "PerInstance" then 
			while wait(1/10) do 
				self:DoJob()
			end 
		else 
			error(self.Mode .. " mode is unknown for archer. Aborting.")
		end 
	end)))
end 

-- Manually call job is possible.
-- If called with nil; loop over all instances, do all jobs. Little haxxy
function Archer:DoJob(Job)
	for NodeIdent, Node in pairs(self.Tree) do 
		local Delta = 0
		for Index = 1, #Node do 
			local UseIndex = Index-Delta
			local Target = Node[UseIndex]
			self.Iterations = self.Iterations + 1 -- This job parsing method has weight 1
			self:CheckIter()

			-- if not in workspace then remove

			local DidChangeNode, IsRemoved = self:ParseInstance(Target, NodeIdent, Job, Index)
			if DidChangeNode then 
				Delta = Delta + 1
			end 
		end 
	end 
end 

-- Manually call for given instance is possible too.
-- If no job is provided, parse all jobs for given target.
function Archer:ParseInstance(Target, NodeIdent, Job, Index)
	local DidChangeNode, IsRemoved = self:ValidateNode(NodeIdent, Target, Index)
	if not IsRemoved then 
		local Position = self:GetPosition(Target)

		-- HAX
		for _, Job in pairs((Job and {Job}) or self.Jobs) do 
				-- Must we run?
				self.Iterations = self.Iterations + 1 -- This job parsing method has weight 1
				self:CheckIter()

				if Job:ShouldRun(Target) then 
					-- check for runfirst
					if Job.ParseSelfFirst then 
						local Weight = Job:ParseSelfFirst(Target)
						if Weight then 
							self.Iterations = self.Iterations + 1
							self:CheckIter()
						end 
					end

					-- Do for targets
					local Range = Job.Range or self.Range
					-- special case check.
					if Range > 0 then 
						local Nodes, NodeIdentifiers = self:GetNearbyNodes(Position, Range)
						for _, TargetNodeData in pairs(Nodes) do 
							local TargetNode = TargetNodeData.TargetNode
							local TNodeIdent = TargetNodeData.TNodeIdent
							local Delta = 0
							for Index = 1, #TargetNode do 
								local Inst = TargetNode[Index-Delta]

								local NodeChanged, GotRemoved, CNode = self:ValidateNode(TNodeIdent, Inst, Index-Delta)
								if NodeChanged then 
									Delta = Delta + 1 
								end 
								-- If the node is inside the to-check nodes; and not removed from tree, RUN:
								if not GotRemoved and NodeIdentifiers[CNode] then 
									-- And finally, do a RANGE CHECK!!
									local TPos = self:GetPosition(Inst)
									local Magnitude = (TPos - Position).magnitude 
									if Magnitude <= (Job.Range or self.Range) then 
										local Weight = Job:Parse(Inst, Target, Magnitude) or 1
										if Weight then 
											self.Iterations = self.Iterations + Weight 
											self:CheckIter()
										end 
									end
								end 
							end 	
						end 
					end 

					if Job.ParseSelfLast then 
						local Weight = Job:ParseSelfLast(Target)
						if Weight then 
							self.Iterations = self.Iterations + 1
							self:CheckIter()
						end 
					end 
				end 
		 
		end
	end 
	return DidChangeNode, IsRemoved
end	

-- PRIVATE functions --
-- No, there is no "security" here, you should just not call them. This is a common Lua practice.
-- Yes, I can also define them only into the environment but that's not my style 

function Archer:GetNode(Position)
	local X,Y,Z 
	X = math.floor(Position.x/self.Range)*self.Range 
	Y = math.floor(Position.y/self.Range)*self.Range 
	Z = math.floor(Position.z/self.Range)*self.Range 
	return X.."."..Y.."."..Z 
end 

function Archer:Insert(Inst, PosIdent)
	local Exists = self.Tree[PosIdent]
	if not Exists then 
		-- Create new node
		 self.Tree[PosIdent] = {Inst}
	else 
		table.insert(Exists, Inst)
	end
end 

local function dump(t,l)
	for i,v in pairs(t) do
		print(string.rep("   ", (l or 0)) .. tostring(i) .. " : " .. tostring(v))
		if type(v) == "table" then
			dump(v, ( l or 0) + 1)
		end
	end
end

function Archer:Remove(Node, Index)
	table.remove(Node, Index)
	if Index==1 then 
		self.Tree[Node] = nil 
	end 
end 

-- Validate node. If changed, returns "true". If the target is removed from the search tree, returns true as second arg too.
-- Returns current node of Target as third arg.
function Archer:ValidateNode(CurrentNode, Target, Index)

			if not Target:IsDescendantOf(game.Workspace) then 

				self:Remove(CurrentNode, Index)
				return true, true, nil
			else

			-- Not in this node! Remove and Re-Insert

				local Position = self:GetPosition(Target)
				local MyIdent = self:GetNode(Position)
				if MyIdent ~= CurrentNode then 
					print(CurrentNode , 'node')
					self:Remove(self.Tree[CurrentNode], Index)
					self:Insert(Target, MyIdent)
					return true, false, MyIdent 
				end	
			end 
			return false, false, CurrentNode 
end


-- Return a table of all relevent nodes for the given position and range.
-- Range may not be bigger than our own range.
-- In this version, there is a theoretical maximum of 3^3 nodes to be checked.
-- Let's use as less .sqrt as possible
function Archer:GetNearbyNodes(Position, Range)
	local Out = {}
	local Strings = {}
	setmetatable(Out, {__index=table})

	for xdelta = -1, 1 do 
		for ydelta = -1, 1 do 
			for zdelta = -1, 1 do 
					local nVec = {x = Position.x + xdelta * Range, y = Position.y + ydelta * Range, z = Position.z + zdelta * Range}				
				
					local MyNodeString = self:GetNode(nVec)

					if not Strings[MyNodeString] then 
						Strings[MyNodeString] = true 
						if self.Tree[MyNodeString] then 
							Out:insert({TargetNode = self.Tree[MyNodeString], TNodeIdent = MyNodeString})
						end
					end 
			end  
		end 
	end 

	if #Out == 0 then 
		error("Did not find any nodes which per definition is not possible. ")
	end
	return Out, Strings 
end 

function Archer:GetPosition(Inst)
	return assert((Inst:IsA("BasePart") and Inst.Position) or (Inst:IsA("Model") and Inst:GetModelCFrame().p), "Provide a model or basepart")
end 

function Archer:CheckIter()
	if self.Iterations >= self.JobTimer then 
		self.Iterations = 0
		wait(1/10)
	end 
end

return Archer 