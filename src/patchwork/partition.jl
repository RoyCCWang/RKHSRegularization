

mutable struct HyperplaneType{T}
    v::Vector{T}
    c::T
    
    HyperplaneType{T}(v,c) where T = new{T}(v,c)
    HyperplaneType{T}() where T = new{T}()
end

mutable struct PartitionDataType{T}
    hp::HyperplaneType{T}
    X::Vector{Vector{T}}
    global_X_indices::Vector{Int}
    index::Int
end

mutable struct BinaryNode{T}
    data::T
    parent::BinaryNode{T}
    left::BinaryNode{T}
    right::BinaryNode{T}

    # Root constructor
    BinaryNode{T}(data) where T = new{T}(data)
    # Child node constructor
    BinaryNode{T}(data, parent::BinaryNode{T}) where T = new{T}(data, parent)
end
BinaryNode(data) = BinaryNode{typeof(data)}(data)


"""
Mutates parent. Taken from AbstractTrees.jl's example code.
"""
function leftchild!(parent::BinaryNode, data)
    !isdefined(parent, :left) || error("left child is already assigned")
    node = typeof(parent)(data, parent)
    parent.left = node
end

"""
Mutates parent. Taken from AbstractTrees.jl's example code.
"""
function rightchild!(parent::BinaryNode, data)
    !isdefined(parent, :right) || error("right child is already assigned")
    node = typeof(parent)(data, parent)
    parent.right = node
end

"""
Taken from AbstractTrees.jl's example code.
"""
function AbstractTrees.children(node::BinaryNode)
    if isdefined(node, :left)
        if isdefined(node, :right)
            return (node.left, node.right)
        end
        return (node.left,)
    end
    isdefined(node, :right) && return (node.right,)
    return ()
end

function splitpoints(u::Vector{T}, X::Vector{Vector{T}}) where T <: Real
    
    N = length(X)
    indicators = falses(N)

    functional_evals = collect( dot(u, X[n]) for n = 1:N )
    c = Statistics.median(functional_evals)

    for n = 1:N
        
        if functional_evals[n] < c

            indicators[n] = true
        else
            indicators[n] = false
        end
    end

    return indicators, functional_evals, c
end 


function gethyperplane(X::Vector{Vector{T}}) where T
    
    # center.
    μ = Statistics.mean(X)
    Z = collect( X[n] - μ for n = 1:size(X,2) )

    Z_mat = (array2matrix(Z))'
    U, s, V = svd(Z_mat)
    v = V[:,1]

    indicators, functional_evals, c = splitpoints(v, X)
    hp = HyperplaneType{T}(v, c)

    return hp, indicators
end


"""
current node is p.
"""
function setuppartition(X::Vector{Vector{T}}, level) where T

    # get hyperplane.
    hp, left_indicators = gethyperplane(X)
    
    X_empty = Vector{Vector{T}}(undef, 0)
    #data = PartitionDataType(hp, X_empty, 0)

    X_empty_inds = Vector{Int}(undef, 0)
    data = PartitionDataType(hp, X_empty, X_empty_inds, 0)

    # add to current node.
    root = BinaryNode(data)

    # might have to use recursion.
    X_inds = collect(1:length(X))
    createchildren(root, left_indicators, "left", X, X_inds, level-1)
    createchildren(root, left_indicators, "right", X, X_inds, level-1)
    
    # assign consecutive whole numbers as indices for the leaf nodes.
    X_parts, X_parts_inds = labelleafnodes(root, X)

    return root, X_parts, X_parts_inds
end

function labelleafnodes(root::BinaryNode{PartitionDataType{T}},
    X::Vector{Vector{T}}) where T
    #
    
    X_parts = Vector{Vector{Vector{Float64}}}(undef, 0)
    X_parts_inds = Vector{Vector{Int}}(undef, 0)
    leaves = Vector{BinaryNode{PartitionDataType{T}}}(undef, 0)

    i = 0
    for node in AbstractTrees.Leaves(root)
        
        # label.
        i += 1
        node.data.index = i
        
        # get X_parts.
        push!(X_parts, X[node.data.global_X_indices])
        push!(X_parts_inds, node.data.global_X_indices)
        
        # sanity check.
        if !isempty(node.data.X)
            @assert norm(node.data.X-X_parts[end]) < 1e-10
        end
        
        #push!(node, leaves) # cache for speed.
    end

    return X_parts, X_parts_inds
end

# might need to include other data, like kernel matrix, etc. at the leaf nodes.
"""
X_p is X associated with parent.
If the input level value is 1, then kid is a leaf node.
"""
function createchildren(parent,
    left_indicators, direction, X_p::Vector{Vector{T}}, X_p_inds::Vector{Int},
    level::Int;
    store_X_flag::Bool = false) where T

    ## prepare children data.
    X_kid = Vector{Vector{T}}(undef, 0)
    X_kid_inds = Vector{Int}(undef, 0)

    if direction == "left"

        X_kid = X_p[left_indicators]
        X_kid_inds = X_p_inds[left_indicators]
        data = PartitionDataType(HyperplaneType{T}(), X_kid, X_kid_inds, 0)

        kid = leftchild!(parent, data)

    else
        right_indicators = .! left_indicators
        X_kid = X_p[right_indicators]
        X_kid_inds = X_p_inds[right_indicators]
        data = PartitionDataType(HyperplaneType{T}(), X_kid, X_kid_inds, 0)

        kid = rightchild!(parent, data)
    end

    if level == 1
        ## kid is a leaf node. Stop propagation.

        if !store_X_flag
            # do not store inputs leaf nodes.
            kid.data.X = Vector{Vector{T}}(undef, 0)
        end
        
        return nothing
    end

    ## kid is not a leaf node. Propagate.

    # do not store inputs and input info at non-leaf nodes. It is not used during query: i.e., findpartition().
    kid.data.X = Vector{Vector{T}}(undef, 0)
    kid.data.global_X_indices = Vector{Int}(undef, 0)

    # get hyperplane.
    hp_kid, left_indicators_kid = gethyperplane(X_kid)
    kid.data.hp = hp_kid

    createchildren(kid, left_indicators_kid, "left", X_kid, X_kid_inds, level-1)
    createchildren(kid, left_indicators_kid, "right", X_kid, X_kid_inds, level-1)

    return nothing
end

#### get all leaves.
# function buildXpart!(X_parts::Vector{Vector{Vector{T}}}, p::BinaryNode{PartitionDataType{T}}) where T

#     #
#     if !isdefined(p, :left) && !isdefined(p, :right)
#         # p is a leaf node. Add its X to X_parts.
#         push!(X_parts, p.data.X)

#         return nothing
#     end

#     # call itself to traverse again.
#     if isdefined(p, :left)
#         buildXpart!(X_parts, p.left)
#     end

#     if isdefined(p, :right)
#         buildXpart!(X_parts, p.right)
#     end
    
#     return nothing
# end

###### search-related.

"""
Given a point and the tree, find the leaf node of the tree that corresponds to the region that contains this point.
"""
function findpartition(x::Vector{T},
    root::BinaryNode{PartitionDataType{T}},
    levels::Int) where T

    #
    node = root
    for l = 1:levels-1
        if dot(node.data.hp.v, x) < node.data.hp.c
            node = node.left
        else
            node = node.right
        end
    end

    return node.data.index
end


"""
Given a point, the tree, a radius, and hyperplanes, find all hyperplanes that intersect a ball centered at x with the supplied radius.
"""
function findnearbyboundaries(root::BinaryNode{PartitionDataType{T}}) where T
    #
    
    X_parts = Vector{Vector{Vector{Float64}}}(undef, 0)
    leaves = Vector{BinaryNode{PartitionDataType{T}}}(undef, 0)

    i = 0
    for node in AbstractTrees.Leaves(root)
        
        i += 1
        node.data.index = i
        push!(X_parts, node.data.X)
        
        # colision detection of a circle and line.
        # https://stackoverflow.com/questions/1073336/circle-line-segment-collision-detection-algorithm
        # allow all regions, even not connected to X_q, to participate.
        #   hopefully this makes the math analysis easier, since avoid some if-else statements.
        
    end

    return X_parts
end