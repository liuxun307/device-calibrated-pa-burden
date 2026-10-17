### Fig 5(d). Decomposition of the gap between device-based and GBD 2023 LPA-attributable burden

**English.** Waterfall decomposition of the ratio (*fold*) between the primary device-based estimate and the burden reported by GBD 2023 for low physical activity (Global, 2022; adults aged 25+; eight causes combined; deaths). Bars show the population-attributable fraction (PAF) under successively aligned definitions. Starting from the primary estimate (PAF = 0.174; fold = 5.72), aligning the excess-risk amplitude of the pooled relative-risk curve to the level implied by the official GBD PAF (mean RR below the TMREL, 1.39 -> 1.04) lowers the estimate to PAF = 0.020 (fold = 0.64); further moving the theoretical minimum-risk exposure level (TMREL) from the absolute threshold used here (54.1th percentile of the population exposure distribution) to the GBD definition (85th percentile) raises it to PAF = 0.030 (fold = 0.99). The residual discrepancy is x1.007 (0.7%), i.e. the two named definitional differences fully account for the gap. The whisker on the first bar shows the range across the eight study locations; the last bar indicates the PAF reported by GBD 2023.

**中文.** 本研究基于设备测量的主估计与 GBD 2023 低体力活动归因负担之比值（fold）的瀑布分解（全球，2022 年；25 岁以上成人；8 个 cause 合计；死亡口径）。纵轴为归因分数（PAF）。自本研究主结果（PAF = 0.174；fold = 5.72）出发，先将池化相对风险曲线的超额风险幅度对齐至官方 PAF 反算的隐含水平（TMREL 之下人群的平均 RR：1.39 → 1.04），估计值降至 PAF = 0.020（fold = 0.64）；再将理论最低风险暴露水平（TMREL）由本文采用的绝对阈值（人群暴露分布第 54.1 百分位）移至 GBD 定义（第 85 百分位），估计值升至 PAF = 0.030（fold = 0.99）。残余差异仅 x1.007（0.7%），即上述两项可命名的口径差异已完全解释该差距。首柱误差棒为 8 个研究地区的范围；末柱为 GBD 2023 现报值。

**Notes / 说明**

- Vertical axis / 纵轴：PAF（归因死亡分数），Global 2022，男女合计，25 岁以上。
- *fold* = PAF(本研究) / PAF(GBD 2023 现报) = PAF / 0.0304；分母为全局常数。
- 'RR magnitude' = 把池化设备测量曲线的超额风险幅度对齐到官方 PAF 反算的隐含水平；'TMREL definition' = 把 TMREL 移到人群暴露分布第 85 百分位（GBD 定义）。
- 残余柱（Residual）按设计几乎不可见：两项可命名的口径差异之后，差距已不足 1%（实测 0.72%）。
- 数据源：`output/Table9_m3_scenario_summary.csv` + `output/Table4_m3_decomp.csv`（由 `code/97_m3_scenarios.R` 产出）；绘图脚本 `code/07_fig5d_waterfall.R`；逐段数值见 `output/Fig5d_waterfall_data.csv`。
- 补充图 `Fig5d_waterfall_by_region` 给出 8 个地区同一分解（GBD_FAITHFUL 的 fold band 0.989–0.999）。
