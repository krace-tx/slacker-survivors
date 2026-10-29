import { z } from 'zod';
import { getGodotConnection } from '../utils/godot_connection.js';
import { MCPTool, CommandResult } from '../utils/types.js';

/**
 * Type definitions for node tool parameters
 */
interface CreateNodeParams {
  parent_path: string;
  node_type: string;
  node_name: string;
}

interface DeleteNodeParams {
  node_path: string;
}

interface UpdateNodePropertyParams {
  node_path: string;
  property: string;
  value: any;
}

interface GetNodePropertiesParams {
  node_path: string;
}

interface ListNodesParams {
  parent_path: string;
}

/**
 * Definition for node tools - operations that manipulate nodes in the scene tree
 */
export const nodeTools: MCPTool[] = [
  {
    name: 'create_node',
    description: 'Create a new node in the Godot scene tree',
    parameters: z.object({
      parent_path: z.string()
        .describe('Path to the parent node where the new node will be created (e.g. "/root", "/root/MainScene")'),
      node_type: z.string()
        .describe('Type of node to create (e.g. "Node2D", "Sprite2D", "Label")'),
      node_name: z.string()
        .describe('Name for the new node'),
    }),
    execute: async ({ parent_path, node_type, node_name }: CreateNodeParams): Promise<string> => {
      const godot = getGodotConnection();
      
      try {
        const result = await godot.sendCommand<CommandResult>('create_node', {
          parent_path,
          node_type,
          node_name,
        });
        
        return `Created ${node_type} node named "${node_name}" at ${result.node_path}`;
      } catch (error) {
        throw new Error(`Failed to create node: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'delete_node',
    description: 'Delete a node from the Godot scene tree',
    parameters: z.object({
      node_path: z.string()
        .describe('Path to the node to delete (e.g. "/root/MainScene/Player")'),
    }),
    execute: async ({ node_path }: DeleteNodeParams): Promise<string> => {
      const godot = getGodotConnection();
      
      try {
        await godot.sendCommand('delete_node', { node_path });
        return `Deleted node at ${node_path}`;
      } catch (error) {
        throw new Error(`Failed to delete node: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'update_node_property',
    description: 'Update a property of a node in the Godot scene tree',
    parameters: z.object({
      node_path: z.string()
        .describe('Path to the node to update (e.g. "/root/MainScene/Player")'),
      property: z.string()
        .describe('Name of the property to update (e.g. "position", "text", "modulate")'),
      value: z.any()
        .describe('New value for the property'),
    }),
    execute: async ({ node_path, property, value }: UpdateNodePropertyParams): Promise<string> => {
      const godot = getGodotConnection();
      
      try {
        const result = await godot.sendCommand<CommandResult>('update_node_property', {
          node_path,
          property,
          value,
        });
        
        return `Updated property "${property}" of node at ${node_path} to ${JSON.stringify(value)}`;
      } catch (error) {
        throw new Error(`Failed to update node property: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'get_node_properties',
    description: 'Get all properties of a node in the Godot scene tree',
    parameters: z.object({
      node_path: z.string()
        .describe('Path to the node to inspect (e.g. "/root/MainScene/Player")'),
    }),
    execute: async ({ node_path }: GetNodePropertiesParams): Promise<string> => {
      const godot = getGodotConnection();
      
      try {
        const result = await godot.sendCommand<CommandResult>('get_node_properties', { node_path });
        
        // Format properties for display
        const formattedProperties = Object.entries(result.properties)
          .map(([key, value]) => `${key}: ${JSON.stringify(value)}`)
          .join('\n');
        
        return `Properties of node at ${node_path}:\n\n${formattedProperties}`;
      } catch (error) {
        throw new Error(`Failed to get node properties: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'list_nodes',
    description: 'List all child nodes under a parent node in the Godot scene tree',
    parameters: z.object({
      parent_path: z.string()
        .describe('Path to the parent node (e.g. "/root", "/root/MainScene")'),
    }),
    execute: async ({ parent_path }: ListNodesParams): Promise<string> => {
      const godot = getGodotConnection();
      
      try {
        const result = await godot.sendCommand<CommandResult>('list_nodes', { parent_path });
        
        if (result.children.length === 0) {
          return `No child nodes found under ${parent_path}`;
        }
        
        // Format children for display
        const formattedChildren = result.children
          .map((child: any) => `${child.name} (${child.type}) - ${child.path}`)
          .join('\n');
        
        return `Children of node at ${parent_path}:\n\n${formattedChildren}`;
      } catch (error) {
        throw new Error(`Failed to list nodes: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'connect_signal',
    description: 'Connect a signal from source node to target node method (persists in scene file)',
    parameters: z.object({
      source_node: z.string().describe('Source node path'),
      signal_name: z.string().describe('Signal name to connect (e.g. pressed, timeout)'),
      target_node: z.string().describe('Target node path'),
      method_name: z.string().describe('Target method name'),
      persist: z.boolean().default(true).describe('Whether to persist in scene file'),
    }),
    execute: async ({ source_node, signal_name, target_node, method_name, persist = true }: any): Promise<string> => {
      const godot = getGodotConnection();
      try {
        await godot.sendCommand('connect_signal', { source_node, signal_name, target_node, method_name, persist });
        return `Connected ${source_node}.${signal_name} -> ${target_node}.${method_name}`;
      } catch (error) {
        throw new Error(`Failed to connect signal: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'disconnect_signal',
    description: 'Disconnect a signal between source node and target node',
    parameters: z.object({
      source_node: z.string().describe('Source node path'),
      signal_name: z.string().describe('Signal name'),
      target_node: z.string().describe('Target node path'),
      method_name: z.string().describe('Target method name'),
    }),
    execute: async ({ source_node, signal_name, target_node, method_name }: any): Promise<string> => {
      const godot = getGodotConnection();
      try {
        await godot.sendCommand('disconnect_signal', { source_node, signal_name, target_node, method_name });
        return `Disconnected ${source_node}.${signal_name} from ${target_node}.${method_name}`;
      } catch (error) {
        throw new Error(`Failed to disconnect signal: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'list_signals',
    description: 'List all signals and active connections on a node',
    parameters: z.object({
      node_path: z.string().describe('Node path to inspect'),
    }),
    execute: async ({ node_path }: any): Promise<string> => {
      const godot = getGodotConnection();
      try {
        const result = await godot.sendCommand('list_signals', { node_path });
        return `Signals for ${node_path}:\n\n` + JSON.stringify(result, null, 2);
      } catch (error) {
        throw new Error(`Failed to list signals: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'set_anchor_preset',
    description: 'Set Control node layout anchor preset (e.g. full_rect, center, top_wide)',
    parameters: z.object({
      node_path: z.string().describe('Control node path'),
      preset: z.string().describe('Preset name (full_rect, center, top_wide, bottom_wide, top_left, etc.)'),
      keep_offsets: z.boolean().default(false).describe('Whether to preserve current offsets'),
    }),
    execute: async ({ node_path, preset, keep_offsets = false }: any): Promise<string> => {
      const godot = getGodotConnection();
      try {
        await godot.sendCommand('set_anchor_preset', { node_path, preset, keep_offsets });
        return `Set anchor preset "${preset}" on ${node_path}`;
      } catch (error) {
        throw new Error(`Failed to set anchor preset: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'set_size_flags',
    description: 'Set container size flags for Control node (horizontal/vertical)',
    parameters: z.object({
      node_path: z.string().describe('Control node path'),
      horizontal: z.string().optional().describe('Horizontal flag (fill, expand, expand_fill, shrink_center)'),
      vertical: z.string().optional().describe('Vertical flag (fill, expand, expand_fill, shrink_center)'),
    }),
    execute: async ({ node_path, horizontal = '', vertical = '' }: any): Promise<string> => {
      const godot = getGodotConnection();
      try {
        await godot.sendCommand('set_size_flags', { node_path, horizontal, vertical });
        return `Set size flags on ${node_path}: H=${horizontal}, V=${vertical}`;
      } catch (error) {
        throw new Error(`Failed to set size flags: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'instantiate_scene',
    description: 'Instantiate an existing .tscn or .glb PackedScene prefab as a child node',
    parameters: z.object({
      parent_path: z.string().default('/root').describe('Parent node path'),
      scene_path: z.string().describe('PackedScene resource path (e.g. "res://src/.../slot_card.tscn")'),
      node_name: z.string().optional().describe('Optional explicit name for the instanced node'),
    }),
    execute: async ({ parent_path = '/root', scene_path, node_name = '' }: any): Promise<string> => {
      const godot = getGodotConnection();
      try {
        const result = await godot.sendCommand('instantiate_scene', { parent_path, scene_path, node_name });
        return `Instantiated ${scene_path} as "${result.node_name}" at ${result.node_path}`;
      } catch (error) {
        throw new Error(`Failed to instantiate scene: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'set_unique_name',
    description: 'Enable or disable scene-unique name (%NodeName) on a node',
    parameters: z.object({
      node_path: z.string().describe('Target node path'),
      enabled: z.boolean().default(true).describe('Whether unique_name_in_owner is enabled'),
    }),
    execute: async ({ node_path, enabled = true }: any): Promise<string> => {
      const godot = getGodotConnection();
      try {
        const result = await godot.sendCommand('set_unique_name', { node_path, enabled });
        return `Set unique_name_in_owner=${enabled} on ${result.node_path} (${result.unique_name})`;
      } catch (error) {
        throw new Error(`Failed to set unique name: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'move_node',
    description: 'Reorder child index or reparent a node within the edited scene tree',
    parameters: z.object({
      node_path: z.string().describe('Target node path'),
      new_parent_path: z.string().optional().describe('Optional new parent node path'),
      index: z.number().default(-1).describe('Target child index (-1 appends or keeps current)'),
    }),
    execute: async ({ node_path, new_parent_path = '', index = -1 }: any): Promise<string> => {
      const godot = getGodotConnection();
      try {
        const result = await godot.sendCommand('move_node', { node_path, new_parent_path, index });
        return `Moved node to ${result.node_path} (index=${result.index})`;
      } catch (error) {
        throw new Error(`Failed to move node: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'get_scene_tree',
    description: 'Get recursive scene tree hierarchy snapshot with script, prefab, and layout info',
    parameters: z.object({
      root_path: z.string().default('/root').describe('Subtree root path'),
      max_depth: z.number().default(8).describe('Maximum recursion depth'),
    }),
    execute: async ({ root_path = '/root', max_depth = 8 }: any): Promise<string> => {
      const godot = getGodotConnection();
      try {
        const result = await godot.sendCommand('get_scene_tree', { root_path, max_depth });
        return JSON.stringify(result, null, 2);
      } catch (error) {
        throw new Error(`Failed to get scene tree: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'set_theme_override',
    description: 'Set Control theme override (constant, color, font_size, or stylebox from res:// / StyleBoxFlat dict)',
    parameters: z.object({
      node_path: z.string().describe('Target Control node path'),
      override_type: z.enum(['constant', 'color', 'font_size', 'stylebox']).describe('Override category'),
      name: z.string().describe('Theme item name (e.g. separation, margin_left, font_color, panel)'),
      value: z.any().describe('Override value (int, #hex/{r,g,b,a}, res://...tres, or StyleBoxFlat dict)'),
    }),
    execute: async ({ node_path, override_type, name, value }: any): Promise<string> => {
      const godot = getGodotConnection();
      try {
        const result = await godot.sendCommand('set_theme_override', { node_path, override_type, name, value });
        return `Applied ${result.property} on ${result.node_path}`;
      } catch (error) {
        throw new Error(`Failed to set theme override: ${(error as Error).message}`);
      }
    },
  },
];