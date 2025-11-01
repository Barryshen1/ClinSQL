WITH admissions_cohort AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
        pa.gender,
        (pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year)) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp`.admissions AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.patients AS pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'M'
        AND (pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year)) BETWEEN 67 AND 77
        -- Filter for primary diagnosis of Acute Decompensated Heart Failure
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd AS di
            WHERE
                di.subject_id = ad.subject_id
                AND di.hadm_id = ad.hadm_id
                AND di.seq_num = 1 -- Primary diagnosis
                AND (
                    (di.icd_version = 10 AND di.icd_code IN ('I5020', 'I5021', 'I5023', 'I5030', 'I5031', 'I5033', 'I5040', 'I5041', 'I5043', 'I50811')) OR
                    (di.icd_version = 9 AND di.icd_code IN ('42821', '42831', '42841'))
                )
        )
),
admission_features AS (
    SELECT
        ac.subject_id,
        ac.hadm_id,
        ac.hospital_expire_flag,
        CASE
            WHEN ac.los_days <= 7 THEN 'LOS <= 7 days'
            ELSE 'LOS > 7 days'
        END AS los_category,
        -- Check for ICU stay within first 24 hours of admission
        MAX(CASE
            WHEN icu.stay_id IS NOT NULL AND icu.intime >= ac.admittime AND icu.intime < DATETIME_ADD(ac.admittime, INTERVAL 1 DAY) THEN 1
            ELSE 0
        END) AS had_icu_in_day1,
        -- Check for CKD diagnosis during admission (any diagnosis, not just primary)
        MAX(CASE
            WHEN di_ckd.icd_code IS NOT NULL THEN 1
            ELSE 0
        END) AS has_ckd,
        -- Check for Diabetes diagnosis during admission (any diagnosis, not just primary)
        MAX(CASE
            WHEN di_dm.icd_code IS NOT NULL THEN 1
            ELSE 0
        END) AS has_diabetes
    FROM
        admissions_cohort AS ac
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu`.icustays AS icu
        ON ac.subject_id = icu.subject_id AND ac.hadm_id = icu.hadm_id
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd AS di_ckd
        ON ac.subject_id = di_ckd.subject_id
        AND ac.hadm_id = di_ckd.hadm_id
        AND (
            (di_ckd.icd_version = 10 AND di_ckd.icd_code LIKE 'N18%') OR -- N18: Chronic kidney disease
            (di_ckd.icd_version = 9 AND di_ckd.icd_code LIKE '585%')    -- 585: Chronic kidney disease
        )
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd AS di_dm
        ON ac.subject_id = di_dm.subject_id
        AND ac.hadm_id = di_dm.hadm_id
        AND (
            (di_dm.icd_version = 10 AND (di_dm.icd_code LIKE 'E10%' OR di_dm.icd_code LIKE 'E11%' OR di_dm.icd_code LIKE 'E12%' OR di_dm.icd_code LIKE 'E13%')) OR -- E10-E13: Diabetes Mellitus
            (di_dm.icd_version = 9 AND di_dm.icd_code LIKE '250%')    -- 250: Diabetes Mellitus
        )
    GROUP BY
        ac.subject_id, ac.hadm_id, ac.hospital_expire_flag, ac.los_days
)
SELECT
    af.los_category,
    -- Make the Day-1 ICU status more descriptive for the final output
    CASE
        WHEN af.had_icu_in_day1 = 1 THEN 'Day-1 ICU Stay'
        ELSE 'No Day-1 ICU Stay'
    END AS day_1_icu_status,
    COUNT(af.hadm_id) AS total_admissions,
    ROUND(SUM(af.hospital_expire_flag) * 100.0 / COUNT(af.hadm_id), 2) AS in_hospital_mortality_percent,
    ROUND(SUM(af.has_ckd) * 100.0 / COUNT(af.hadm_id), 2) AS ckd_prevalence_percent,
    ROUND(SUM(af.has_diabetes) * 100.0 / COUNT(af.hadm_id), 2) AS diabetes_prevalence_percent
FROM
    admission_features AS af -- Correctly alias the CTE directly in FROM clause
GROUP BY
    af.los_category,
    af.had_icu_in_day1 -- Use the correct column name
ORDER BY
    af.los_category,
    af.had_icu_in_day1; -- Use the correct column name;