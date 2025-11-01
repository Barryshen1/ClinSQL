WITH HF_COHORT AS (
    -- Step 1: Identify male HF patients aged 38-48 with their admission details
    SELECT DISTINCT
        p.subject_id,
        ad.hadm_id,
        p.gender,
        p.anchor_age,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON p.subject_id = ad.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_icd
        ON ad.hadm_id = diag_icd.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 38 AND 48
        AND diag_icd.icd_version = 10
        AND diag_icd.icd_code LIKE 'I50%' -- Heart Failure ICD-10 code
),
CHARLSON_CONDITIONS AS (
    -- Step 2a: Identify presence of common Charlson conditions for each admission
    -- Each condition is flagged (1 if present, 0 if absent) derived from ICD-10 codes.
    -- Note: This is an implementation for Charlson mapping. Full Charlson calculation
    -- might require more nuanced code mapping and exclusion rules.
    SELECT
        hfc.hadm_id,
        -- Common Charlson conditions and their ICD-10 patterns.
        MAX(CASE WHEN REGEXP_CONTAINS(diag_icd.icd_code, '^I2[12]') THEN 1 ELSE 0 END) AS mi, -- Myocardial infarction (1 point)
        MAX(CASE WHEN REGEXP_CONTAINS(diag_icd.icd_code, '^I50') THEN 1 ELSE 0 END) AS chf, -- Congestive heart failure (1 point)
        MAX(CASE WHEN REGEXP_CONTAINS(diag_icd.icd_code, '^(I70|K550|Z95812)') THEN 1 ELSE 0 END) AS pvd, -- Peripheral vascular disease (1 point)
        MAX(CASE WHEN REGEXP_CONTAINS(diag_icd.icd_code, '^(I6[0-9]|G45[.-][0-9]|H34)') THEN 1 ELSE 0 END) AS cvd, -- Cerebrovascular disease (1 point)
        MAX(CASE WHEN REGEXP_CONTAINS(diag_icd.icd_code, '^(F0[0-3]|G30)') THEN 1 ELSE 0 END) AS dementia, -- Dementia (1 point)
        MAX(CASE WHEN REGEXP_CONTAINS(diag_icd.icd_code, '^J4[0-7]') THEN 1 ELSE 0 END) AS copd, -- Chronic pulmonary disease (1 point)
        MAX(CASE WHEN REGEXP_CONTAINS(diag_icd.icd_code, '^(M0[56]|M315|M351|M353)') THEN 1 ELSE 0 END) AS rheumatic, -- Rheumatic disease (1 point)
        MAX(CASE WHEN REGEXP_CONTAINS(diag_icd.icd_code, '^K2[5-7]') THEN 1 ELSE 0 END) AS peptic_ulcer, -- Peptic ulcer disease (1 point)
        MAX(CASE WHEN REGEXP_CONTAINS(diag_icd.icd_code, '^(K70[139]|K71[3-5]|K73|K74[0-2]|K76[09])') THEN 1 ELSE 0 END) AS mild_liver, -- Mild liver disease (1 point)
        MAX(CASE WHEN REGEXP_CONTAINS(diag_icd.icd_code, '^(E1[0-4][.-][01])') THEN 1 ELSE 0 END) AS diabetes_uncomplicated, -- Diabetes without complications (1 point)
        MAX(CASE WHEN REGEXP_CONTAINS(diag_icd.icd_code, '^(E1[0-4][.-][2-8])') THEN 1 ELSE 0 END) AS diabetes_complicated, -- Diabetes with complications (2 points)
        MAX(CASE WHEN REGEXP_CONTAINS(diag_icd.icd_code, '^(G041|G114|G8[0-3])') THEN 1 ELSE 0 END) AS hemiplegia, -- Hemiplegia or paraplegia (2 points)
        MAX(CASE WHEN REGEXP_CONTAINS(diag_icd.icd_code, '^(N0[0-7]|N1[7-9]|I120|I13[12])') THEN 1 ELSE 0 END) AS renal, -- Renal disease (2 points)
        
        -- Refined malignancy logic to avoid REGEXP_CONTAINS lookahead.
        -- First, identify any C00-C96 cancer. Use SAFE_CAST for robustness.
        MAX(CASE WHEN SUBSTR(diag_icd.icd_code, 1, 1) = 'C' 
                 AND SAFE_CAST(SUBSTR(diag_icd.icd_code, 2, 2) AS INT64) BETWEEN 0 AND 96 THEN 1 ELSE 0 END) AS malignancy_all_cancers,
        -- Then, identify metastatic cancer (C77-C80). Use SAFE_CAST for robustness.
        MAX(CASE WHEN SUBSTR(diag_icd.icd_code, 1, 1) = 'C' 
                 AND SAFE_CAST(SUBSTR(diag_icd.icd_code, 2, 2) AS INT64) BETWEEN 77 AND 80 THEN 1 ELSE 0 END) AS metastatic_cancer, -- Metastatic solid tumor (6 points)

        MAX(CASE WHEN REGEXP_CONTAINS(diag_icd.icd_code, '^(B18|C22|I85[09]|I982|K704|K711|K72[19]|K74[3-6]|K76[2-46-8]|R18)') THEN 1 ELSE 0 END) AS severe_liver, -- Severe liver disease (3 points)
        MAX(CASE WHEN REGEXP_CONTAINS(diag_icd.icd_code, '^(B2[0-4]|Z21)') THEN 1 ELSE 0 END) AS aids -- AIDS/HIV (6 points)
    FROM
        HF_COHORT hfc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_icd
        ON hfc.hadm_id = diag_icd.hadm_id
    WHERE diag_icd.icd_version = 10
    GROUP BY
        hfc.hadm_id
),
CHARLSON_SCORE_PER_ADMISSION AS (
    -- Step 2b: Sum the points to get the total Charlson score per admission
    SELECT
        hadm_id,
        (
            mi * 1 +
            chf * 1 +
            pvd * 1 +
            cvd * 1 +
            dementia * 1 +
            copd * 1 +
            rheumatic * 1 +
            peptic_ulcer * 1 +
            mild_liver * 1 +
            -- Diabetes: 2 points for complications, 1 for uncomplicated, 0 if neither
            GREATEST(diabetes_complicated * 2, diabetes_uncomplicated * 1) +
            hemiplegia * 2 +
            renal * 2 +
            -- Malignancy logic:
            -- If metastatic_cancer is present (6 points), use 6 points.
            -- Else if other malignancy (C00-C96, excluding C77-C80) is present, use 2 points.
            GREATEST(
                metastatic_cancer * 6,
                CASE WHEN malignancy_all_cancers = 1 AND metastatic_cancer = 0 THEN 2 ELSE 0 END
            ) +
            severe_liver * 3 +
            aids * 6
        ) AS charlson_score
    FROM
        CHARLSON_CONDITIONS
),
ADMISSION_DETAILS AS (
    -- Step 3, 4, 5: Consolidate admission data with stratification variables
    SELECT
        hfc.subject_id,
        hfc.hadm_id,
        hfc.hospital_expire_flag,
        COALESCE(cs.charlson_score, 0) AS charlson_score, -- Default to 0 if no Charlson conditions found
        -- Step 3: Determine ICU stay
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
                WHERE icu.hadm_id = hfc.hadm_id
            ) THEN 'Yes'
            ELSE 'No'
        END AS icu_stay_group,
        -- Step 4: Calculate and categorize LOS
        DATE_DIFF(hfc.dischtime, hfc.admittime, DAY) AS los_days,
        CASE
            WHEN DATE_DIFF(hfc.dischtime, hfc.admittime, DAY) IS NULL THEN 'Unknown'
            WHEN DATE_DIFF(hfc.dischtime, hfc.admittime, DAY) <= 0 THEN '0 days or less'
            WHEN DATE_DIFF(hfc.dischtime, hfc.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN DATE_DIFF(hfc.dischtime, hfc.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
            WHEN DATE_DIFF(hfc.dischtime, hfc.admittime, DAY) >= 8 THEN '>=8 days'
            ELSE 'Unknown'
        END AS los_group,
        -- Step 5: Categorize Charlson scores
        CASE
            WHEN COALESCE(cs.charlson_score, 0) <= 3 THEN '<=3'
            WHEN COALESCE(cs.charlson_score, 0) BETWEEN 4 AND 5 THEN '4-5'
            WHEN COALESCE(cs.charlson_score, 0) > 5 THEN '>5'
            ELSE 'Unknown' -- For any unexpected null/invalid scores
        END AS charlson_group
    FROM
        HF_COHORT hfc
    LEFT JOIN
        CHARLSON_SCORE_PER_ADMISSION cs
        ON hfc.hadm_id = cs.hadm_id
)
-- Step 6 & 7: Calculate final aggregate statistics with 95% CI
SELECT
    icu_stay_group,
    los_group,
    charlson_group,
    COUNT(DISTINCT hadm_id) AS total_admissions,
    ROUND(SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(DISTINCT hadm_id)) * 100, 2) AS in_hospital_mortality_percent,

    -- Calculate 95% Confidence Interval for mortality rate using aggregate values per group
    -- Z-score for 95% CI is approximately 1.96
    ROUND(
        (SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(DISTINCT hadm_id)) -
        1.96 * SQRT(
            SAFE_DIVIDE(
                SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(DISTINCT hadm_id)) * (1 - SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(DISTINCT hadm_id))),
                COUNT(DISTINCT hadm_id)
            )
        )) * 100, 2
    ) AS mortality_ci_lower_percent,
    ROUND(
        (SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(DISTINCT hadm_id)) +
        1.96 * SQRT(
            SAFE_DIVIDE(
                SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(DISTINCT hadm_id)) * (1 - SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(DISTINCT hadm_id))),
                COUNT(DISTINCT hadm_id)
            )
        )) * 100, 2
    ) AS mortality_ci_upper_percent,
    
    ROUND(AVG(charlson_score), 2) AS mean_comorbidity_count
FROM
    ADMISSION_DETAILS t
GROUP BY
    icu_stay_group,
    los_group,
    charlson_group
ORDER BY
    icu_stay_group,
    los_group,
    charlson_group;