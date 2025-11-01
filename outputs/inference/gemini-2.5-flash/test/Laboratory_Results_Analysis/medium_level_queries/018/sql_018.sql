WITH acs_admissions AS (
    -- Identify unique admissions for male patients aged 90-100 with an ACS diagnosis
    SELECT DISTINCT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp`.admissions ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.patients p
        ON ad.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
        ON ad.hadm_id = di.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 90 AND 100
        -- Filter for Acute Coronary Syndrome (ACS) ICD codes
        -- Common ICD-10 codes for STEMI/NSTEMI start with I21
        -- Common ICD-9 codes for MI start with 410
        AND (
            (di.icd_version = 10 AND di.icd_code LIKE 'I21%')
            OR (di.icd_version = 9 AND di.icd_code LIKE '410%')
        )
),
first_troponin_t AS (
    -- Get the first Troponin T measurement for each admission
    SELECT
        le.hadm_id,
        le.valuenum AS troponin_t_val,
        ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
    FROM
        `physionet-data.mimiciv_3_1_hosp`.labevents le
    WHERE
        le.itemid = 51003 -- Itemid for Troponin T (refer to d_labitems table)
        AND le.valuenum IS NOT NULL
        AND le.valuenum >= 0 -- Exclude potentially erroneous negative values
),
categorized_troponin_admissions AS (
    -- Join ACS admissions with their first Troponin T measurement and categorize
    SELECT
        ap.hadm_id,
        DATETIME_DIFF(ap.dischtime, ap.admittime, HOUR) / 24.0 AS los_days,
        CASE
            WHEN ft.troponin_t_val < 0.01 THEN 'Normal (<0.01 ng/mL)'
            WHEN ft.troponin_t_val >= 0.01 AND ft.troponin_t_val < 0.03 THEN 'Borderline (0.01-0.03 ng/mL)'
            WHEN ft.troponin_t_val >= 0.03 THEN 'Elevated (>=0.03 ng/mL)'
            ELSE 'Unknown/Uncategorized' -- Should ideally not be reached given `valuenum` filters
        END AS troponin_category
    FROM
        acs_admissions ap
    INNER JOIN
        first_troponin_t ft
        ON ap.hadm_id = ft.hadm_id
    WHERE
        ft.rn = 1 -- Select only the first Troponin T measurement for each admission
)
-- Final aggregation to calculate counts, percentages, and mean LOS
SELECT
    troponin_category,
    COUNT(DISTINCT hadm_id) AS admission_count,
    ROUND(COUNT(DISTINCT hadm_id) * 100.0 / SUM(COUNT(DISTINCT hadm_id)) OVER(), 2) AS percentage,
    ROUND(AVG(los_days), 2) AS mean_los_days
FROM
    categorized_troponin_admissions
GROUP BY
    troponin_category
ORDER BY
    -- Order by category severity for logical presentation
    CASE troponin_category
        WHEN 'Normal (<0.01 ng/mL)' THEN 1
        WHEN 'Borderline (0.01-0.03 ng/mL)' THEN 2
        WHEN 'Elevated (>=0.03 ng/mL)' THEN 3
        ELSE 99
    END;