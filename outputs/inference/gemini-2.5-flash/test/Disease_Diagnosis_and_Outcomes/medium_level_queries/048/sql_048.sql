SELECT
    los_group,
    COUNT(hadm_id) AS total_heart_failure_admissions, -- COUNT(DISTINCT hadm_id) is slightly less efficient but works; COUNT(hadm_id) is fine here since hadm_id is distinct per row from the GROUP BY in the subquery
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(hadm_id), 2) AS in_hospital_mortality_percent,
    ROUND(SUM(has_ckd) * 100.0 / COUNT(hadm_id), 2) AS ckd_prevalence_percent,
    ROUND(SUM(has_diabetes) * 100.0 / COUNT(hadm_id), 2) AS diabetes_prevalence_percent
FROM (
    SELECT
        ap.subject_id,
        ap.hadm_id,
        ap.hospital_expire_flag,
        -- Calculate LOS and then assign to los_group
        CASE
            WHEN DATE_DIFF(ap.dischtime, ap.admittime, DAY) < 8 THEN '<8 days'
            ELSE '>=8 days'
        END AS los_group,
        MAX(CASE
            -- Heart Failure ICD-9 and ICD-10 codes
            WHEN diag.icd_version = 9 AND diag.icd_code LIKE '428%' THEN 1
            WHEN diag.icd_version = 10 AND diag.icd_code LIKE 'I50%' THEN 1
            ELSE 0
        END) AS has_heart_failure,
        MAX(CASE
            -- CKD ICD-9 and ICD-10 codes
            WHEN diag.icd_version = 9 AND diag.icd_code LIKE '585%' THEN 1
            WHEN diag.icd_version = 10 AND diag.icd_code LIKE 'N18%' THEN 1
            ELSE 0
        END) AS has_ckd,
        MAX(CASE
            -- Diabetes Mellitus ICD-9 and ICD-10 codes
            WHEN diag.icd_version = 9 AND diag.icd_code LIKE '250%' THEN 1
            WHEN diag.icd_version = 10 AND diag.icd_code BETWEEN 'E10' AND 'E149' THEN 1 -- E10% to E14%
            ELSE 0
        END) AS has_diabetes
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ap
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ap.subject_id = p.subject_id
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON ap.subject_id = diag.subject_id AND ap.hadm_id = diag.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 68 AND 78
        AND ap.dischtime IS NOT NULL -- Ensure LOS can be calculated reliably
    GROUP BY
        ap.subject_id,
        ap.hadm_id,
        ap.hospital_expire_flag,
        -- Need to include the new los_group calculation in GROUP BY
        CASE
            WHEN DATE_DIFF(ap.dischtime, ap.admittime, DAY) < 8 THEN '<8 days'
            ELSE '>=8 days'
        END
) AS admissions_with_flags
WHERE
    has_heart_failure = 1 -- Filter for the heart failure cohort
GROUP BY
    los_group
ORDER BY
    los_group;