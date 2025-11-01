WITH base_cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime, 
        adm.hospital_expire_flag,
        pat.anchor_age,
        -- Classify MI type: use first MI diagnosis (lowest seq_num)
        FIRST_VALUE(
            CASE 
                WHEN icd.icd_code LIKE 'I21.0%' OR icd.icd_code LIKE 'I21.1%' 
                    OR icd.icd_code LIKE 'I21.2%' OR icd.icd_code LIKE 'I21.3%' THEN 'STEMI'
                WHEN icd.icd_code LIKE 'I21.4%' THEN 'NSTEMI'
            END 
            IGNORE NULLS
        ) OVER (PARTITION BY adm.hadm_id ORDER BY diag.seq_num) AS mi_type
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
        ON diag.icd_code = icd.icd_code AND diag.icd_version = icd.icd_version
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 51 AND 61
        AND (icd.icd_code LIKE 'I21.0%' OR icd.icd_code LIKE 'I21.1%' 
             OR icd.icd_code LIKE 'I21.2%' OR icd.icd_code LIKE 'I21.3%' 
             OR icd.icd_code LIKE 'I21.4%')
),
-- Remove duplicates by taking distinct hadm_id with mi_type
distinct_cohort AS (
    SELECT 
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        hospital_expire_flag,
        anchor_age,
        mi_type
    FROM base_cohort
    WHERE mi_type IS NOT NULL
    GROUP BY subject_id, hadm_id, admittime, dischtime, hospital_expire_flag, anchor_age, mi_type
),
-- Calculate LOS and group
cohort_with_los AS (
    SELECT 
        *,
        DATE_DIFF(dischtime, admittime, DAY) AS los_days,
        CASE 
            WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 2 THEN '1-2'
            WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 3 AND 5 THEN '3-5'
            WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 6 AND 9 THEN '6-9'
            WHEN DATE_DIFF(dischtime, admittime, DAY) >= 10 THEN '>=10'
            ELSE 'Other'
        END AS los_group
    FROM distinct_cohort
),
-- Comorbidity flags: define a set of comorbidities (example: diabetes, CKD, CHF, pulmonary, liver, cancer)
-- We'll use a list of ICD-10 codes for each. Here we define diabetes and CKD explicitly, and others for count.
comorbidities AS (
    SELECT 
        hadm_id,
        -- Diabetes flags
        MAX(CASE WHEN icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' 
                  OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%' THEN 1 ELSE 0 END) AS diabetes_flag,
        -- CKD flags
        MAX(CASE WHEN icd_code LIKE 'N18%' OR icd_code = 'N19' OR icd_code LIKE 'I12%' 
                  OR icd_code LIKE 'I13%' OR icd_code LIKE 'N17%' OR icd_code LIKE 'N16%' THEN 1 ELSE 0 END) AS ckd_flag,
        -- Other comorbidities for count: we define a few more
        MAX(CASE WHEN icd_code LIKE 'I50%' THEN 1 ELSE 0 END) AS chf_flag,
        MAX(CASE WHEN icd_code LIKE 'J4%' OR icd_code LIKE 'J5%' OR icd_code LIKE 'J6%' 
                  OR icd_code LIKE 'J7%' THEN 1 ELSE 0 END) AS pulmonary_flag,
        MAX(CASE WHEN icd_code LIKE 'K70%' OR icd_code LIKE 'K71%' OR icd_code LIKE 'K72%' 
                  OR icd_code LIKE 'K73%' OR icd_code LIKE 'K74%' THEN 1 ELSE 0 END) AS liver_flag,
        MAX(CASE WHEN icd_code LIKE 'C%' OR icd_code LIKE 'D0%' OR icd_code LIKE 'D1%' 
                  OR icd_code LIKE 'D2%' OR icd_code LIKE 'D3%' THEN 1 ELSE 0 END) AS cancer_flag
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
),
-- Compute comorbidity count and group
cohort_comorbid AS (
    SELECT 
        c.*,
        co.diabetes_flag,
        co.ckd_flag,
        (co.diabetes_flag + co.ckd_flag + co.chf_flag + co.pulmonary_flag + co.liver_flag + co.cancer_flag) AS comorbidity_count,
        CASE 
            WHEN (co.diabetes_flag + co.ckd_flag + co.chf_flag + co.pulmonary_flag + co.liver_flag + co.cancer_flag) <= 1 THEN '0-1'
            WHEN (co.diabetes_flag + co.ckd_flag + co.chf_flag + co.pulmonary_flag + co.liver_flag + co.cancer_flag) = 2 THEN '2'
            ELSE '>=3'
        END AS comorbidity_group
    FROM cohort_with_los c
    LEFT JOIN comorbidities co
        ON c.hadm_id = co.hadm_id
)
-- Final aggregation
SELECT 
    mi_type,
    los_group,
    comorbidity_group,
    COUNT(*) AS n,
    ROUND(100 * AVG(hospital_expire_flag), 2) AS mortality_percent,
    ROUND(100 * AVG(ckd_flag), 2) AS ckd_prevalence_percent,
    ROUND(100 * AVG(diabetes_flag), 2) AS diabetes_prevalence_percent
FROM cohort_comorbid
GROUP BY mi_type, los_group, comorbidity_group
ORDER BY mi_type, los_group, comorbidity_group;