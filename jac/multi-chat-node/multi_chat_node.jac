# jac/multi-chat-node/multi_chat_node.jac
# Ported from the ai-chat-network prototype: a small node/edge graph shape
# demo (two nodes fanning into one), not LLM-backed. The original also had
# a dangling `can log_ai_walker` declaration with no body or `with` clause
# -- not valid under old or current Jac -- dropped here since it was never
# implemented.

node MultiChatNode {
    has conversations: str = "";

    can log_entry with entry {
        print(f">>> Someone entered the node: {self}");
    }
}

with entry:__main__ {
    # Multiple nodes connect to a single node: many to one.
    first_tier = [MultiChatNode() for i in range(2)];
    second_node = MultiChatNode();
    root ++> first_tier;
    for n in first_tier {
        n ++> second_node;
    }
}
