#!/biodata/dep_psl/grp_rgo/tools/bin/Rscript

library(plyr)
library(parallelDist)
library(dplyr)
library(tidyr)
library(gridExtra)

source("../00.common_scripts/plot_settings.R")
source("../00.common_scripts/pcoa_plotting.R")
source("../00.common_scripts/hist_settings.R")

asv_file <- "../00.data/final_ASV/Fungi/ASV_table_1104.rds"
design_file <- "../00.data/design.txt"
tax_file <- "../00.data/final_ASV/Fungi/ASV_taxonomy.txt"
alpha_file <- "../00.data/alpha_diversity/alpha_Fungi.txt"
kingdom <- "Fungi"

###############################################################################
## For relative abundance histogram
source("./script_figure_s7_pre.R")

p <- ggplot(data = asv_tax_sum,
             aes(x = Group2, y = x,
                 fill = Phylum)) +
    geom_bar(stat = "identity", position = "stack") +
    scale_x_discrete(limits = order_new) +
    main_theme + scale_fill_manual(values = as.character(c_Fun$color)) +
    theme(legend.position = "top",
          axis.text.x = element_text(colour = "black", angle = 90,
                                     size = 4, hjust = 1)) +
    labs(x = "", y = "")

ggsave("Figure_S7a.pdf", p, width = 16, height = 10)

###############################################################################
## for B and C, phylum based PCoA and density plot
asv <- readRDS(asv_file)
design <- read.table(design_file, header = T, sep = "\t")
tax <- read.table(tax_file, header = T, sep = "\t")

# Tidy up tax to make it the same as histogram
tax$Phylum <- as.character(tax$Phylum)
tax$Phylum[is.na(tax$Phylum)] <- "Unassigned"

tax <- tax[, 1 : 2]
tax <- tax[rownames(tax) %in% rownames(asv), ]
# dim = 9880 * 2

group <- as.factor(tax$Phylum)
group_lst <- as.character(levels(group))
asv <- asv[match(rownames(tax), rownames(asv)), ]
asv <- apply(asv, 2, function(x) x / sum(x))
asv_tax <- apply(asv, 2, function(x) rowsum(x, group))
rownames(asv_tax) <- group_lst

bc <- parDist(t(asv_tax), method = "bray")
bc_mat <- as.matrix(bc)
dmr <- cmdscale(bc_mat, k = 4, eig = T)

design <- design[match(rownames(bc_mat), design$Sample_ID), ]
p_s7b <- pcoa(dmr, design, 12, "Compartment", "Stage", 2.4, kingdom) +
    theme(legend.position = "none")

## for density plot
dis_asv_mat <- as.matrix(parDist(t(asv), method = "bray"))
dis_tax_mat <- bc_mat

## filter design
design <- design[, colnames(design) %in% c("Sample_ID", "Compartment", "Stage",
                                            "Compartment_Stage")]

design_asv <- design[, colnames(design) %in% c("Sample_ID",
                                               "Compartment_Stage")]
colnames(design_asv) <- c("Compare", "Compare_Group")

############################################  at the ASV level
asv_dis <- c()
for ( i in 1: nrow(dis_asv_mat)){
    this <- data.frame(Sample_ID = rownames(dis_asv_mat)[i],
                       Compare = colnames(dis_asv_mat),
                       Dis = dis_asv_mat[i, ])
    this <- merge(this, design_asv)
    this <- this %>% group_by(Compare_Group) %>%
            mutate(Dis_Mean = mean(Dis))

    this_mean <- this[, colnames(this) %in%
            c("Sample_ID", "Compare_Group", "Dis_Mean")]
    this_mean <- unique(this_mean)

    asv_dis <- rbind(asv_dis, this_mean)
}

this_asv_filter <- asv_dis[asv_dis$Compare_Group == "Bulksoil_before_sowing" |
                           asv_dis$Compare_Group == "Root_Reproductive", ]

this_asv_filter <- this_asv_filter %>% spread(Compare_Group, Dis_Mean)
this_asv_filter <- merge(this_asv_filter, design)

############################################  at the Phylum level
tax_dis <- c()
for ( i in 1: nrow(dis_tax_mat)){
    this <- data.frame(Sample_ID = rownames(dis_tax_mat)[i],
                       Compare = colnames(dis_tax_mat),
                       Dis = dis_tax_mat[i, ])
    this <- merge(this, design_asv)
    this <- this %>% group_by(Compare_Group) %>%
    mutate(Dis_Mean = mean(Dis))

    this_mean <- this[, colnames(this) %in%
            c("Sample_ID", "Compare_Group", "Dis_Mean")]
    this_mean <- unique(this_mean)

    tax_dis <- rbind(tax_dis, this_mean)
}

this_tax_filter <- tax_dis[tax_dis$Compare_Group == "Bulksoil_before_sowing" |
                           tax_dis$Compare_Group == "Root_Reproductive", ]
this_tax_filter <- this_tax_filter %>% spread(Compare_Group, Dis_Mean)
this_tax_filter <- merge(this_tax_filter, design)

##########################################  density plot

############## at the ASV level
## reduce 2D to 1D by calculating Euclidean distance
nr <- nrow(this_asv_filter)
ASV <- c()
# set sample with smalles mean dissimilarity to Bulksoil_before_sowing sample
# as control, Sample_ID is 544H
min_x <- min(this_asv_filter[, 2])
x0 <- min_x
y0 <- this_asv_filter[this_asv_filter[, 2] == min_x, 3]

for (n in 1 : nr ){
    ## for Bulksoil_before_sowing
    xn <- this_asv_filter[n, 2]
    ## for Root_Reproductive
    yn <- this_asv_filter[n, 3]
    dis <- sqrt((xn - x0) ** 2 + (yn - y0) **2)
    this <- c(as.character(this_asv_filter[n, 1]),
              as.character(this_asv_filter[n, 6]), dis)
    ASV <- rbind(ASV, this)
}

colnames(ASV) <- c("Sample_ID", "Compartment_Stage", "Distance")
ASV <- as.data.frame(ASV)
ASV$Distance <- as.numeric(as.character(ASV$Distance))
ASV$Compartment_Stage <- as.character(ASV$Compartment_Stage)

df_mean <- ASV %>% group_by(Compartment_Stage) %>%
    summarise(Mean = mean(Distance))
write.table(df_mean, "Figure_S7c_ASV_mean.txt",
            quote = F, sep = "\t", row.names = F)

lines_mean <- as.numeric(as.character(df_mean$Mean))
colors <- c(br[c(1, 2, 4)], oranges[c(6, 3)], greens[c(6, 3)])

p_s7c_1 <- ggplot(ASV, aes(Distance, fill = Compartment_Stage)) +
        geom_density(alpha = 0.7, size = 0.2, color = "wheat4") +
        scale_fill_manual(values = c_Com_Sta) +
        main_theme +
        theme(legend.position = "none", axis.title = element_blank()) +
        geom_vline(xintercept = lines_mean, color = colors,
                   linetype = "longdash")

############## at the phylum level
nr <- nrow(this_tax_filter)
TAX <- c()

min_x <- min(this_tax_filter[, 2])
x0 <- min_x
y0 <- this_asv_filter[this_tax_filter[, 2] == min_x, 3]

for( n in 1 : nr  ){
    xn <- this_tax_filter[n, 2]
    yn <- this_tax_filter[n, 3]
    dis <- sqrt((xn - x0) ** 2 + (yn - y0) **2)
    this <- c(as.character(this_tax_filter[n, 1]),
              as.character(this_tax_filter[n, 6]), dis)
    TAX <- rbind(TAX, this)
}

colnames(TAX) <- c("Sample_ID", "Compartment_Stage", "Distance")
TAX <- as.data.frame(TAX)
TAX$Distance <- as.numeric(as.character(TAX$Distance))
TAX$Compartment_Stage <- as.character(TAX$Compartment_Stage)

df_mean <- TAX %>% group_by(Compartment_Stage) %>%
    summarise(Mean = mean(Distance))
write.table(df_mean, "Figure_S7c_TAX_mean.txt",
            quote = F, sep = "\t", row.names = F)
lines_mean <- as.numeric(as.character(df_mean$Mean))

p_s7c_2 <- ggplot(TAX, aes(Distance, fill = Compartment_Stage)) +
        geom_density(alpha = 0.7, size = 0.2, color = "wheat4") +
        scale_fill_manual(values = c_Com_Sta) +
        main_theme +
        theme(legend.position = "none", axis.title = element_blank()) +
        geom_vline(xintercept = lines_mean, color = colors,
                   linetype = "longdash")

## put together
library(cowplot)
p_s7c <- plot_grid(p_s7c_1, p_s7c_2,
                       p_s7c_1, p_s7c_2,
                       p_s7c_1, p_s7c_2,
                       nrow = 6, ncol = 1,
                       align = "v", axis = "l")

p <- plot_grid(p_s7b, p_s7c, nrow = 1, ncol = 2)
ggsave("Figure_S7bc.pdf", p, width = 10, height = 5)

###############################################################################
## Statistical test
lst <- unique(ASV$Compartment_Stage)
len <- length(lst)

sig <- c()
for (i in 1 : (len -1)) {
    this_i <- ASV[ASV$Compartment_Stage == lst[i], ]
    for (j in (i + 1) : len) {
        this_j <- ASV[ASV$Compartment_Stage == lst[j], ]
        p <- wilcox.test(as.numeric(as.character(this_i$Distance)),
                         as.numeric(as.character(this_j$Distance)))
        this_sig <- c(lst[i], lst[j], p$p.value)
        sig <- rbind(sig, this_sig)
    }
}

colnames(sig) <- c("Group1", "Group2", "Significance")
sig <- as.data.frame(sig)
sig$Significance <- as.numeric(as.character(sig$Significance))
sig$Sig <- ifelse(sig$Significance < 0.05, TRUE, FALSE)
sig$FDR <- p.adjust(sig$Significance, method = "fdr")
sig$Sig_FDR <- ifelse(as.numeric(as.character(sig$FDR)) < 0.05,
                        TRUE, FALSE)

write.table(sig, "Figure_S7c_ASV_sig.txt", quote = F, sep = "\t", row.names = F)

sig <- c()
for (i in 1 : (len -1)) {
    this_i <- TAX[TAX$Compartment_Stage == lst[i], ]
    for (j in (i + 1) : len) {
        this_j <- TAX[TAX$Compartment_Stage == lst[j], ]
        p <- wilcox.test(as.numeric(as.character(this_i$Distance)),
                         as.numeric(as.character(this_j$Distance)))
        this_sig <- c(lst[i], lst[j], p$p.value)
        sig <- rbind(sig, this_sig)
    }
}

colnames(sig) <- c("Group1", "Group2", "Significance")
sig <- as.data.frame(sig)
sig$Significance <- as.numeric(as.character(sig$Significance))
sig$Sig <- ifelse(sig$Significance < 0.05, TRUE, FALSE)
sig$FDR <- p.adjust(sig$Significance, method = "fdr")
sig$Sig_FDR <- ifelse(as.numeric(as.character(sig$FDR)) < 0.05,
                        TRUE, FALSE)

write.table(sig, "Figure_S7c_TAX_sig.txt", quote = F, sep = "\t", row.names = F)
