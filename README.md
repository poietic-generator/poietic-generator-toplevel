# Poietic Generator (umbrella project :umbrella:)

<!-- inspired by https://github.com/marp-team/marp -->

The Poietic Generator probe is a multiplayer and collaborative anoptic experiment 

This repository ([@poietic-generator/poietic-generator](https://github.com/poietic-generator/poietic-generator)) is an entrance to the Poietic Generator probe project and components family, website and project-wide utilities.

## Prerequisites

You need Docker and Make installed on your system

## Usage

    make build
    make run

## Components

### API Servers

| Name | Description |
|---   |---          |
| [api-ruby](https://github.com/poietic-generator/poietic-generator-api-ruby) | :heavy_check_mark: __Production version.__<br/> First web version. Naive implementation of the poietic-generator probe based on web constraintes. No new features will be added there. |
| [api-crystal](https://github.com/poietic-generator/poietic-generator-api-crystal) | :arrow_right: __Development version.__<br/> API re-implementation adding support for real-time (websockets) and mesh network (peer-to-peer nodes). |
| [api-ocaml](https://github.com/poietic-generator/poietic-generator-api-ocaml) | :x: __Experiment.__<br/> Playground for web services in OCaml |


### User interfaces

| Name | Description |
|---   |---          |
| [ui-jquery](https://github.com/poietic-generator/poietic-generator-ui-jquery) | :heavy_check_mark: __Production version.__<br/> First web version : early 2010 implementation based on jQuery + jQuery mobile. No new features will be added there. |
| [ui-vue](https://github.com/poietic-generator/poietic-generator-ui-vue) | :arrow_right: __Development version.__<br/>  |
| [ui-phaser](https://github.com/poietic-generator/poietic-generator-ui-phaser) | :x: __Experiment__.<br/> Playground for smartphone version |


## Utilities

| Name | Description |
|---   |---          |
| [cli-ruby](https://github.com/poietic-generator/poietic-generator-api-ruby) | :heavy_check_mark: __Production version.__<br/> Command-line utility to manage sessions groups, and to extract snapshots images and videos |


## Roadmap

* :arrow_right: __Develop a minimal front-end in VueJS + Typescript__ : The "component-by-component" development logic will make it easier to upgrade and replace interface elements. In addition, it will be easier to decline to a mobile version.
  * using the current Ruby API
  * allow navigation in sessions
  * allow the reading of an old session
  * allow participation in the game
* :arrow_right: __Rewrite the API in Crystal__ : Crystal is a programming language that is partialy compatible with ruby and uses its syntax. It also provides an advanced typing system that facilitates bug detection, compilation and much better performance.
* :x: __Add support for websocket in the Crystal API + VueJS front-end.__
* :x: __Add unicast p2p (WAN nodes <=> WAN nodes) support__
* :x: __Add unicast c/s (WAN nodes <=> WAN renderers) support__
* :x: __Add unicast c/s (WAN nodes <=> WAN controlers) support__
* :x: __Add multicast p2p (LAN nodes <=> LAN nodes) support__
* :x: __Add multicast c/s (LAN nodes <=> LAN renderers) support__
* :x: __Add multicast c/s (LAN nodes <=> LAN controlers) support__

