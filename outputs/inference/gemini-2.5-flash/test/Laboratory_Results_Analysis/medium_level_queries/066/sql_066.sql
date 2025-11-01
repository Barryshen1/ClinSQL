WITH cohort_admissions AS (
    -- Step 1: Identify the target patient cohort - men aged 39-49 admitted for chest pain.
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dicd
        ON adm.subject_id = dicd.subject_id AND adm.hadm_id = dicd.hadm_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 39 AND 49 -- Anchor age represents age at the time of their first admission
        AND (
            (dicd.icd_version = 9 AND dicd.icd_code LIKE '7865%') -- ICD-9 codes for chest pain (e.g., 786.5, 786.50, 786.51, 786.52, 786.59)
            OR (dicd.icd_version = 10 AND dicd.icd_code LIKE 'R07%') -- ICD-10 codes for chest pain (e.g., R07, R07.0, R07.1, R07.2, R07.3, R07.4)
        )
),
initial_hstat AS (
    -- Step 2: Extract the initial high-sensitivity Troponin T (hs-TnT) level for each admission in the cohort.
    SELECT
        ca.subject_id,
        ca.hadm_id,
        le.valuenum AS initial_hstat_value
    FROM
        cohort_admissions AS ca
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON ca.subject_id = le.subject_id AND ca.hadm_id = le.hadm_id
    WHERE
        le.itemid = 51003 -- Itemid for 'Troponin T' in d_labitems, often high-sensitivity in modern MIMIC-IV data sources
        AND le.valuenum IS NOT NULL -- Exclude rows without a numeric result
        AND le.valueuom = 'ng/mL' -- Ensure units are consistent with clinical cutoffs
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ca.hadm_id ORDER BY le.charttime) = 1 -- Get the first measurement for each admission
),
categorized_hstat AS (
    -- Step 3: Categorize the initial hs-TnT levels based on defined clinical cutoffs.
    -- Cutoffs for hs-TnT (ref: commonly accepted clinical guidelines from ng/L to ng/mL):
    --   Normal: < 14 ng/L (0.014 ng/mL)
    --   Borderline: 14 ng/L to 52 ng/L (0.014 ng/mL to 0.052 ng/mL)
    --   Myocardial Injury: > 52 ng/L (> 0.052 ng/mL)
    SELECT
        ih.subject_id,
        ih.hadm_id,
        ih.initial_hstat_value,
        CASE
            WHEN ih.initial_hstat_value < 0.014 THEN 'Normal'
            WHEN ih.initial_hstat_value >= 0.014 AND ih.initial_hstat_value <= 0.052 THEN 'Borderline'
            WHEN ih.initial_hstat_value > 0.052 THEN 'Myocardial Injury'
            ELSE 'Other/Uncategorized' -- Should ideally not be reached if filtered properly
        END AS hs_tnt_category
    FROM
        initial_hstat AS ih
)
-- Step 4: Calculate counts, percentages, mean, median, and IQR for each hs-TnT category.
SELECT
    chs.hs_tnt_category,
    COUNT(chs.hadm_id) AS CountOfAdmissions,
    ROUND(COUNT(chs.hadm_id) * 100.0 / SUM(COUNT(chs.hadm_id)) OVER (), 2) AS Percentage,
    ROUND(AVG(chs.initial_hstat_value), 4) AS Mean_hsTnT,
    ROUND(APPROX_QUANTILES(chs.initial_hstat_value, 4)[OFFSET(2)], 4) AS Median_hsTnT, -- 50th percentile
    ROUND(APPROX_QUANTILES(chs.initial_hstat_value, 4)[OFFSET(1)], 4) AS Q1_hsTnT,       -- 25th percentile
    ROUND(APPROX_QUANTILES(chs.initial_hstat_value, 4)[OFFSET(3)], 4) AS Q3_hsTnT,       -- 75th percentile
    ROUND(APPROX_QUANTILES(chs.initial_hstat_value, 4)[OFFSET(3)] - APPROX_QUANTILES(chs.initial_hstat_value, 4)[OFFSET(1)], 4) AS IQR_hsTnT
FROM
    categorized_hstat AS chs
WHERE
    chs.hs_tnt_category != 'Other/Uncategorized' -- Ensure only desired categories are included in final results
GROUP BY
    chs.hs_tnt_category
ORDER BY
    CASE chs.hs_tnt_category
        WHEN 'Normal' THEN 1
        WHEN 'Borderline' THEN 2
        WHEN 'Myocardial Injury' THEN 3
        ELSE 4 -- Fallback for any unexpected category
    END;