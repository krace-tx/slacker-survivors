import { z } from 'zod';
import { getGodotConnection } from '../utils/godot_connection.js';
import { MCPTool, CommandResult } from '../utils/types.js';

/**
 * Type definitions for scene tool parameters
 */
interface SaveSceneParams {
  path?: string;
}

interface OpenSceneParams {
  path: string;
}

interface CreateSceneParams {
  path: string;
  root_node_type?: string;
  root_node_name?: string;
  base_scene_path?: string;
  root_script?: string;
}

interface CreateResourceParams {
  resource_type: string;
  resource_path: string;
  properties?: Record<string, any>;
}

/**
 * Definition for scene tools - operations that manipulate Godot scenes
 */
export const sceneTools: MCPTool[] = [
  {
    name: 'create_scene',
    description: 'Create a new scene (from root node type or inherited base scene) and save to disk',
    parameters: z.object({
      path: z.string()
        .describe('Path where the new scene will be saved (e.g. "res://scenes/new_scene.tscn")'),
      root_node_type: z.string().optional()
        .describe('Type of root node to create (e.g. "Node2D", "Node3D", "Control"). Defaults to "Node" if not specified'),
      root_node_name: z.string().optional()
        .describe('Optional explicit root node name'),
      base_scene_path: z.string().optional()
        .describe('Optional base .tscn path for scene inheritance'),
      root_script: z.string().optional()
        .describe('Optional .gd script path to attach to root node'),
    }),
    execute: async ({ path, root_node_type = "Node", root_node_name = "", base_scene_path = "", root_script = "" }: CreateSceneParams): Promise<string> => {
      const godot = getGodotConnection();
      
      try {
        const result = await godot.sendCommand<CommandResult>('create_scene', {
          path,
          root_node_type,
          root_node_name,
          base_scene_path,
          root_script,
        });
        return `Created new scene at ${result.scene_path} with root node type ${result.root_node_type}`;
      } catch (error) {
        throw new Error(`Failed to create scene: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'save_scene',
    description: 'Save the current scene to disk',
    parameters: z.object({
      path: z.string().optional()
        .describe('Path where the scene will be saved (e.g. "res://scenes/main.tscn"). If not provided, uses current scene path.'),
    }),
    execute: async ({ path }: SaveSceneParams): Promise<string> => {
      const godot = getGodotConnection();
      
      try {
        const result = await godot.sendCommand<CommandResult>('save_scene', { path });
        return `Saved scene to ${result.scene_path}`;
      } catch (error) {
        throw new Error(`Failed to save scene: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'open_scene',
    description: 'Open a scene in the editor',
    parameters: z.object({
      path: z.string()
        .describe('Path to the scene file to open (e.g. "res://scenes/main.tscn")'),
    }),
    execute: async ({ path }: OpenSceneParams): Promise<string> => {
      const godot = getGodotConnection();
      
      try {
        const result = await godot.sendCommand<CommandResult>('open_scene', { path });
        return `Opened scene at ${result.scene_path}`;
      } catch (error) {
        throw new Error(`Failed to open scene: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'get_current_scene',
    description: 'Get information about the currently open scene',
    parameters: z.object({}),
    execute: async (): Promise<string> => {
      const godot = getGodotConnection();
      
      try {
        const result = await godot.sendCommand<CommandResult>('get_current_scene', {});
        
        return `Current scene: ${result.scene_path}\nRoot node: ${result.root_node_name} (${result.root_node_type})`;
      } catch (error) {
        throw new Error(`Failed to get current scene: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'get_project_info',
    description: 'Get information about the current Godot project',
    parameters: z.object({}),
    execute: async (): Promise<string> => {
      const godot = getGodotConnection();
      
      try {
        const result = await godot.sendCommand<CommandResult>('get_project_info', {});
        
        const godotVersion = `${result.godot_version.major}.${result.godot_version.minor}.${result.godot_version.patch}`;
        
        let output = `Project Name: ${result.project_name}\n`;
        output += `Project Version: ${result.project_version}\n`;
        output += `Project Path: ${result.project_path}\n`;
        output += `Godot Version: ${godotVersion}\n`;
        
        if (result.current_scene) {
          output += `Current Scene: ${result.current_scene}`;
        } else {
          output += "No scene is currently open";
        }
        
        return output;
      } catch (error) {
        throw new Error(`Failed to get project info: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'create_resource',
    description: 'Create a new resource in the project',
    parameters: z.object({
      resource_type: z.string()
        .describe('Type of resource to create (e.g. "ImageTexture", "AudioStreamMP3", "StyleBoxFlat")'),
      resource_path: z.string()
        .describe('Path where the resource will be saved (e.g. "res://resources/style.tres")'),
      properties: z.record(z.any()).optional()
        .describe('Dictionary of property values to set on the resource'),
    }),
    execute: async ({ resource_type, resource_path, properties = {} }: CreateResourceParams): Promise<string> => {
      const godot = getGodotConnection();
      
      try {
        const result = await godot.sendCommand<CommandResult>('create_resource', {
          resource_type,
          resource_path,
          properties,
        });
        
        return `Created ${resource_type} resource at ${result.resource_path}`;
      } catch (error) {
        throw new Error(`Failed to create resource: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'capture_viewport_2d',
    description: 'Capture a screenshot of the 2D editor viewport as base64 or save to path',
    parameters: z.object({
      save_path: z.string().optional().describe('Optional file path to save PNG (e.g. res://screenshot.png)'),
      return_base64: z.boolean().default(true).describe('Whether to return base64 PNG data'),
    }),
    execute: async ({ save_path = '', return_base64 = true }: any): Promise<string> => {
      const godot = getGodotConnection();
      try {
        const result = await godot.sendCommand('capture_viewport_2d', { save_path, return_base64 });
        let out = `Captured 2D viewport (${result.width}x${result.height})`;
        if (result.save_path) out += ` saved to ${result.save_path}`;
        if (result.base64_png) out += `\nBase64 PNG length: ${result.base64_png.length} chars`;
        return out;
      } catch (error) {
        throw new Error(`Failed to capture 2D viewport: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'capture_node',
    description: 'Capture screenshot of a specific 2D/Control node from the viewport',
    parameters: z.object({
      node_path: z.string().describe('Target CanvasItem / Control node path'),
      save_path: z.string().optional().describe('Optional file path to save PNG'),
      return_base64: z.boolean().default(true).describe('Whether to return base64 PNG data'),
    }),
    execute: async ({ node_path, save_path = '', return_base64 = true }: any): Promise<string> => {
      const godot = getGodotConnection();
      try {
        const result = await godot.sendCommand('capture_node', { node_path, save_path, return_base64 });
        let out = `Captured node ${node_path} (${result.width}x${result.height})`;
        if (result.save_path) out += ` saved to ${result.save_path}`;
        return out;
      } catch (error) {
        throw new Error(`Failed to capture node: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'capture_viewport_3d',
    description: 'Capture a screenshot of the 3D editor viewport as base64 or save to path',
    parameters: z.object({
      viewport_index: z.number().default(0).describe('3D editor viewport index (0-3)'),
      save_path: z.string().optional().describe('Optional file path to save PNG'),
      return_base64: z.boolean().default(true).describe('Whether to return base64 PNG data'),
    }),
    execute: async ({ viewport_index = 0, save_path = '', return_base64 = true }: any): Promise<string> => {
      const godot = getGodotConnection();
      try {
        const result = await godot.sendCommand('capture_viewport_3d', { viewport_index, save_path, return_base64 });
        let out = `Captured 3D viewport #${viewport_index} (${result.width}x${result.height})`;
        if (result.save_path) out += ` saved to ${result.save_path}`;
        return out;
      } catch (error) {
        throw new Error(`Failed to capture 3D viewport: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'play_current_scene',
    description: 'Play the currently open edited scene in the Godot editor',
    parameters: z.object({}),
    execute: async (): Promise<string> => {
      const godot = getGodotConnection();
      try {
        const result = await godot.sendCommand('play_current_scene', {});
        return `Started playing current scene: ${result.playing_scene || 'active'}`;
      } catch (error) {
        throw new Error(`Failed to play current scene: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'play_main_scene',
    description: 'Play the main scene of the Godot project',
    parameters: z.object({}),
    execute: async (): Promise<string> => {
      const godot = getGodotConnection();
      try {
        const result = await godot.sendCommand('play_main_scene', {});
        return `Started playing main scene: ${result.playing_scene || 'main'}`;
      } catch (error) {
        throw new Error(`Failed to play main scene: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'stop_game',
    description: 'Stop the currently running game in the editor',
    parameters: z.object({}),
    execute: async (): Promise<string> => {
      const godot = getGodotConnection();
      try {
        const result = await godot.sendCommand('stop_game', {});
        return `Game stopped: ${result.status}`;
      } catch (error) {
        throw new Error(`Failed to stop game: ${(error as Error).message}`);
      }
    },
  },

  {
    name: 'get_game_status',
    description: 'Check whether a game instance is currently running in the editor',
    parameters: z.object({}),
    execute: async (): Promise<string> => {
      const godot = getGodotConnection();
      try {
        const result = await godot.sendCommand('get_game_status', {});
        return `Game status: is_playing=${result.is_playing}, scene=${result.playing_scene || 'none'}`;
      } catch (error) {
        throw new Error(`Failed to get game status: ${(error as Error).message}`);
      }
    },
  },
];