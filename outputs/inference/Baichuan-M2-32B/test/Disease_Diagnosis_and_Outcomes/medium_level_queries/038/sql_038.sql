WITH patient_cohort AS (
    SELECT
        subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
        gender = 'F'
        AND anchor_age BETWEEN 80 AND 90
),
admissions_with_heart_failure AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        -- Calculate LOS in days
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        -- Check for ICU stay: if there's at least one icustay for this admission
        CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS has_icu_stay
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` i
        ON a.hadm_id = i.hadm_id
    WHERE
        a.subject_id IN (SELECT subject_id FROM patient_cohort)
        AND a.dischtime IS NOT NULL  -- Only include completed admissions
        -- Check for heart failure diagnosis in this admission
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
                ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
            WHERE
                d.hadm_id = a.hadm_id
                AND dd.icd_version = 10
                AND dd.icd_code LIKE 'I50%'  -- Heart failure ICD-10 codes
        )
),
ckd_diabetes_flags AS (
    SELECT
        hadm_id,
        -- Check for CKD diagnosis in this admission
        MAX(CASE WHEN dd.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS has_ckd,
        -- Check for diabetes diagnosis in this admission
        MAX(CASE WHEN dd.icd_code LIKE 'E11%' THEN 1 ELSE 0 END) AS has_diabetes
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE
        dd.icd_version = 10
        AND (dd.icd_code LIKE 'N18%' OR dd.icd_code LIKE 'E11%')
    GROUP BY
        hadm_id
)
SELECT
    CASE WHEN has_icu_stay = 1 THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
    CASE WHEN los_days < 8 THEN '<8 days' ELSE '>=8 days' END AS los_category,
    -- In-hospital mortality percentage
    SUM(hospital_expire_flag) * 100.0 / COUNT(*) AS in_hospital_mortality_percent,
    -- CKD prevalence percentage
    AVG(has_ckd) * 100.0 AS ckd_prevalence_percent,
    -- Diabetes prevalence percentage
    AVG(has_diabetes) * 100.0 AS diabetes_prevalence_percent
FROM
    admissions_with_heart_failure a
LEFT JOIN
    ckd_diabetes_flags c
    ON a.hadm_id = c.hadm_id
GROUP BY
    icu_status,
    los_category
ORDER BY
    icu_status,
    los_category;