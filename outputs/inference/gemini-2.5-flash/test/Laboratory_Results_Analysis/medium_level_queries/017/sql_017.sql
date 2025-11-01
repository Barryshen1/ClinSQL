SELECT
    -- Calculate the median Troponin-T value
    PERCENTILE_CONT(FirstTroponinT.troponin_t_value, 0.5) OVER() AS median_troponin_t_g_per_ml,
    -- Calculate the 25th percentile (Q1) Troponin-T value
    PERCENTILE_CONT(FirstTroponinT.troponin_t_value, 0.25) OVER() AS q1_troponin_t_g_per_ml,
    -- Calculate the 75th percentile (Q3) Troponin-T value
    PERCENTILE_CONT(FirstTroponinT.troponin_t_value, 0.75) OVER() AS q3_troponin_t_g_per_ml,
    -- Calculate the Interquartile Range (IQR)
    (PERCENTILE_CONT(FirstTroponinT.troponin_t_value, 0.75) OVER() - PERCENTILE_CONT(FirstTroponinT.troponin_t_value, 0.25) OVER()) AS iqr_troponin_t_g_per_ml
FROM
    -- First, identify the cohort of admissions
    (
        SELECT DISTINCT
            adm.subject_id,
            adm.hadm_id
        FROM
            `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.patients` AS pat
            ON adm.subject_id = pat.subject_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
            ON adm.hadm_id = diag.hadm_id
        WHERE
            pat.gender = 'M'
            AND pat.anchor_age BETWEEN 47 AND 57
            AND (
                -- ICD-9 codes for Ischemic Heart Disease (410-414)
                (diag.icd_version = 9 AND (
                    diag.icd_code LIKE '410%' OR
                    diag.icd_code LIKE '411%' OR
                    diag.icd_code LIKE '412%' OR
                    diag.icd_code LIKE '413%' OR
                    diag.icd_code LIKE '414%'
                ))
                OR
                -- ICD-10 codes for Ischemic Heart Disease (I20-I25)
                (diag.icd_version = 10 AND (
                    diag.icd_code LIKE 'I20%' OR
                    diag.icd_code LIKE 'I21%' OR
                    diag.icd_code LIKE 'I22%' OR
                    diag.icd_code LIKE 'I23%' OR
                    diag.icd_code LIKE 'I24%' OR
                    diag.icd_code LIKE 'I25%'
                ))
            )
    ) AS CohortAdmissions
INNER JOIN
    -- Next, get the first Troponin-T measurement for each admission
    (
        SELECT
            le.hadm_id,
            le.valuenum AS troponin_t_value,
            ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
        FROM
            `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        WHERE
            le.itemid = 50933 -- itemid for 'Troponin T'
            AND le.valuenum IS NOT NULL
            AND le.valueuom = 'ng/mL' -- Ensure the correct unit
    ) AS FirstTroponinT
    ON CohortAdmissions.hadm_id = FirstTroponinT.hadm_id
WHERE
    FirstTroponinT.rn = 1 -- Only consider the first Troponin-T measurement for each admission
    AND FirstTroponinT.troponin_t_value > 0.014 -- Filter for values exceeding 0.014 ng/mL
LIMIT 1; -- We only need one row for the overall median and IQR;