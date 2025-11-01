WITH sepsis_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
    WHERE
        (
            -- Sepsis ICD-10 codes
            icd_code LIKE 'A40%' OR    -- Streptococcal sepsis
            icd_code LIKE 'A41%' OR    -- Other sepsis (e.g., A41.9 unspecified sepsis)
            icd_code = 'R65.20' OR     -- Severe sepsis, without septic shock
            -- Sepsis ICD-9 codes
            icd_code LIKE '038%' OR    -- Septicemia
            icd_code = '995.91'        -- Sepsis
        )
),
septic_shock_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
    WHERE
        (
            -- Septic shock ICD-10 codes to exclude
            icd_code = 'R65.21' OR     -- Severe sepsis with septic shock
            icd_code LIKE 'T81.12%' OR -- Postprocedural septic shock (e.g., T81.12XA for ICD-10 code with 7th character)
            -- Septic shock ICD-9 codes to exclude
            icd_code = '785.52' OR     -- Septic shock
            icd_code = '995.92'        -- Severe sepsis (often indicates shock in older definitions)
        )
),
ckd_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
    WHERE
        (icd_code LIKE '585%' AND icd_version = 9) OR -- CKD ICD-9
        (icd_code LIKE 'N18%' AND icd_version = 10)    -- CKD ICD-10
),
diabetes_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
    WHERE
        (icd_code LIKE '250%' AND icd_version = 9) OR -- Diabetes ICD-9
        (icd_code LIKE 'E10%' AND icd_version = 10) OR -- Type 1 Diabetes ICD-10
        (icd_code LIKE 'E11%' AND icd_version = 10) OR -- Type 2 Diabetes ICD-10
        (icd_code LIKE 'E13%' AND icd_version = 10)    -- Other Diabetes ICD-10
),
afib_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
    WHERE
        (icd_code = '427.31' AND icd_version = 9) OR -- AFib ICD-9
        (icd_code LIKE 'I48%' AND icd_version = 10)    -- AFib ICD-10
),
htn_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
    WHERE
        (icd_code LIKE '401%' AND icd_version = 9) OR -- Essential hypertension ICD-9
        (icd_code LIKE '402%' AND icd_version = 9) OR -- Hypertensive heart disease ICD-9
        (icd_code LIKE '403%' AND icd_version = 9) OR -- Hypertensive chronic kidney disease ICD-9
        (icd_code LIKE '404%' AND icd_version = 9) OR -- Hypertensive heart and chronic kidney disease ICD-9
        (icd_code LIKE '405%' AND icd_version = 9) OR -- Secondary hypertension ICD-9
        (icd_code = 'I10' AND icd_version = 10) OR    -- Essential (primary) hypertension ICD-10
        (icd_code LIKE 'I11%' AND icd_version = 10) OR -- Hypertensive heart disease ICD-10
        (icd_code LIKE 'I12%' AND icd_version = 10) OR -- Hypertensive chronic kidney disease ICD-10
        (icd_code LIKE 'I13%' AND icd_version = 10) OR -- Hypertensive heart and chronic kidney disease ICD-10
        (icd_code LIKE 'I15%' AND icd_version = 10)    -- Secondary hypertension ICD-10
),
eligible_admissions AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp`.admissions AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.patients AS p
        ON adm.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 75 AND 85
        -- Filter for sepsis (excluding septic shock)
        AND adm.hadm_id IN (SELECT hadm_id FROM sepsis_admissions)
        AND adm.hadm_id NOT IN (SELECT hadm_id FROM septic_shock_admissions)
),
admissions_with_flags AS (
    SELECT
        ea.hadm_id,
        ea.hospital_expire_flag,
        CASE WHEN ea.los_days <= 5 THEN '<=5 days' ELSE '>5 days' END AS los_group,
        CASE WHEN ckd.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ckd,
        CASE WHEN db.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_diabetes,
        CASE WHEN afib.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_afib,
        CASE WHEN htn.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_hypertension
    FROM
        eligible_admissions AS ea
    LEFT JOIN
        ckd_admissions AS ckd
        ON ea.hadm_id = ckd.hadm_id
    LEFT JOIN
        diabetes_admissions AS db
        ON ea.hadm_id = db.hadm_id
    LEFT JOIN
        afib_admissions AS afib
        ON ea.hadm_id = afib.hadm_id
    LEFT JOIN
        htn_admissions AS htn
        ON ea.hadm_id = htn.hadm_id
)
SELECT
    awf.los_group,
    awf.has_ckd,
    awf.has_diabetes,
    awf.has_afib,
    awf.has_hypertension,
    COUNT(awf.hadm_id) AS total_admissions,
    SUM(awf.hospital_expire_flag) AS in_hospital_deaths,
    ROUND(SUM(awf.hospital_expire_flag) * 100.0 / COUNT(awf.hadm_id), 2) AS mortality_percentage
FROM
    admissions_with_flags AS awf
GROUP BY
    awf.los_group,
    awf.has_ckd,
    awf.has_diabetes,
    awf.has_afib,
    awf.has_hypertension
ORDER BY
    awf.los_group,
    awf.has_ckd,
    awf.has_diabetes,
    awf.has_afib,
    awf.has_hypertension;