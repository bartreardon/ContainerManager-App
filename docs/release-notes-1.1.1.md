# ContainerManager 1.1.1

Lets you say what a new container or volume belongs to, at the point you create it.

## New

**Assign a stack from the create sheet.** New Container and New Volume both have a
**Stack** picker, alongside the name and image. Picking one groups the item with that
stack in the lists, and a container also joins the stack's network — so a helper
alongside an existing stack, a CI runner next to a Gitea instance say, can reach it
without you working out the network by hand.

This was already possible, through a stack's **Add Service…** button, but only if you
knew to look there. Making a container starts at Containers ▸ **+**, and that sheet had
no way to express it.

Worth knowing what joining a stack means: a container is grouped, started and stopped
with it, and **deleted with it**. A volume isn't — deleting a stack keeps its volumes,
as before. Neither is added to the stack's saved definition, so **Re-create** won't
restore them.

## Known limitations

Something can only be assigned to a stack **as it's created**. The runtime accepts
labels when a container or volume is created and offers no way to change them
afterwards, so an existing container can't be moved into a stack — it has to be
re-created. Volumes are the exception: right-click one and use **Set Label…**, which
the app stores itself.

On macOS 27 beta, published ports accept a connection and then reset it, so
`localhost:<port>` doesn't reach a container while its own address still works —
[apple/container#2029](https://github.com/apple/container/issues/2029). This is
upstream and not worked around here.
