# Chirpy 启动模板

[![Gem 版本](https://img.shields.io/gem/v/jekyll-theme-chirpy)][gem]&nbsp;
[![GitHub 许可证](https://img.shields.io/github/license/cotes2020/chirpy-starter.svg?color=blue)][mit]

一款轻量、开箱即用的模板，用于基于 [**Chirpy**][chirpy] Jekyll 主题搭建博客。所有核心文件已预先配置，几分钟即可完成部署。

## 为什么要做这个启动模板

通过 [RubyGems.org][gem] 安装 Chirpy 时，Jekyll 只能读取主题中的部分文件（`_data`、`_layouts`、`_includes`、`_sass`、`assets`）以及 `_config.yml` 里的有限配置项。因此用户无法完整享受到 Chirpy 提供的全部开箱即用功能。

要解锁全部功能，你的 Jekyll 站点必须包含以下文件：

```shell
.
├── _config.yml
├── _plugins
├── _tabs
└── index.html
```

本启动模板打包了最新版 **Chirpy** 中的上述文件，并附带一套[持续部署][CD]工作流，让你可以直接开始写作。

## 使用方法

请查阅[主题官方文档](https://github.com/cotes2020/jekyll-theme-chirpy/wiki)。

## 参与贡献

本仓库会随主题仓库的新版本自动更新。如果你遇到问题或希望参与改进，请前往[主题仓库][chirpy]提交反馈。

## 许可证

本项目基于 [MIT][mit] 许可证发布。

[gem]: https://rubygems.org/gems/jekyll-theme-chirpy
[chirpy]: https://github.com/cotes2020/jekyll-theme-chirpy/
[CD]: https://en.wikipedia.org/wiki/Continuous_deployment
[mit]: https://github.com/cotes2020/chirpy-starter/blob/master/LICENSE
