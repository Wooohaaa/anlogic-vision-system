# LWIP

## 概述

Lwip Add Phy 例程提供如下功能：

- 演示如何在Lwip环境下支持一个新的Phy驱动

## 硬件设置

无特殊设置

## 已知问题

无已知问题

## 运行说明

示例:main.c al_gbe_phy_JL2101.c
- 新添加的Phy驱动文件需要按照al_gbe_phy_JL2101.c中的代码格式，实现对应的Phy结构体以及实现相应函数

    /* 变量 PhyJL2101 定义需要按照以下固定格式 */
    USED const struct AL_PHY_DevStruct PhyJL2101 SECTION("gbe_phy_section") = {
        .PhyName = "JL2101",                        // Phy 名称
        .PhyId = PHY_ID_JL2101,                     // Phy ID
        .PhyPhase100M  = PHY_JL2101_PHASE_100M,     // Phy 100M 相位，当前为RGMII下的相位配置
        .PhyPhase1000M = PHY_JL2101_PHASE_1000M,    // Phy 1000M 相位，当前为RGMII下的相位配置
        .Init = AlPhy_JL2101Init,                   // Phy 初始化函数，配置Phy的寄存器以及发起自协商等
        .GetLinkStatus = AlPhy_JL2101GetLinkStatus, // Phy 获取链接状态函数
        .GetLinkSpeedDuplex = AlPhy_JL2101GetLinkSpeedDuplex,   // Phy 获取链接的速度以及双工能力函数
    };