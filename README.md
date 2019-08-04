# Poietic Generator (umbrella project :umbrella:)

<!-- inspired by https://github.com/marp-team/marp -->

The Poietic Generator probe is a multiplayer and collaborative anoptic experiment 

This repository ([@poietic-generator/poietic-generator](https://github.com/poietic-generator/poietic-generator)) is an entrance to the Poietic Generator probe project and components family, website and project-wide utilities.

## Components

### API Servers

| Name | Description | 
|---   |---          |
| [api-ruby](https://github.com/poietic-generator/poietic-generator-api-ruby) | :heavy_check_mark: __Production version.__<br/> First web version. Naive implementation of the poietic-generator probe based on web constraintes. No new features will be added there. |
| [api-ocaml](https://github.com/poietic-generator/poietic-generator-api-ocaml) | :x: __Experiment.__<br/> Playground for web services in OCaml |
| [api-crystal](https://github.com/poietic-generator/poietic-generator-api-crystal) | :wavy_dash: __Development version.__<br/> API re-implementation adding support for real-time (websockets) and mesh network (peer-to-peer nodes). |

### User interfaces

| Name | Description |
|---   |---          |
| [ui-jquery](https://github.com/poietic-generator/poietic-generator-ui-jquery) | :heavy_check_mark: __Production version.__<br/> First web version : early 2010 implementation based on jQuery + jQuery mobile. No new features will be added there. |
| [ui-phaser](https://github.com/poietic-generator/poietic-generator-ui-phaser) | :x: __Experiment__.<br/> Playground for smartphone version |
| [ui-vue](https://github.com/poietic-generator/poietic-generator-ui-vue) | :wavy_dash: __Development version.__<br/>  |

## Utilities

| Name | Description |
|---   |---          |
| [cli-ruby](https://github.com/poietic-generator/poietic-generator-api-ruby) | :heavy_check_mark: __Production version.__<br/> Command-line utility to manage sessions groups, and to extract snapshots images and videos |

## Roadmap

1. (20%) __Develop a minimal front-end in VueJS + Typescript__ : The "component-by-component" development logic will make it easier to upgrade and replace interface elements. In addition, it will be easier to decline to a mobile version.

   - based on the current Ruby API
   - allow navigation in sessions
   - allow the reading of an old session
   - allow participation in the game

2. (0%) __Rewrite the API in Crystal__ : Crystal is a programming language that is partly compatible with ruby and uses its syntax. It also provides an advanced typing system that facilitates bug detection, compilation and much better performance.

3. (0%) __Add support for websocket in the Crystal API + VueJS front-end.__

