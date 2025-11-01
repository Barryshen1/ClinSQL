WITH admissions_with_age_los AS (
    -- Base cohort: female patients aged 49-59 at admission, with LO to calculate
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        p.gender,
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 49 AND 59
),
sepsis_icd_codes AS (
    -- Define ICD codes for sepsis (to include)
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (
            (icd_version = 9 AND icd_code LIKE '038%')
            OR
            (icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%' OR icd_code = 'R6520'))
        )
),
septic_shock_icd_codes AS (
    -- Define ICD codes for septic shock (to exclude)
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (
            (icd_version = 9 AND icd_code = '78552') -- Septic shock
            OR
            (icd_version = 10 AND icd_code = 'R6521') -- Severe sepsis with septic shock
        )
),
ckd_icd_codes AS (
    -- Define ICD codes for Chronic Kidney Disease
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (
            (icd_version = 9 AND icd_code LIKE '585%')
            OR
            (icd_version = 10 AND icd_code LIKE 'N18%')
        )
),
diabetes_icd_codes AS (
    -- Define ICD codes for Diabetes Mellitus
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (
            (icd_version = 9 AND icd_code LIKE '250%')
            OR
            (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%'))
        )
),
filtered_admissions_cohort AS (
    -- Apply sepsis (no septic shock) filter and add CKD/Diabetes flags
    SELECT
        awa.subject_id,
        awa.hadm_id,
        awa.admittime,
        awa.dischtime,
        awa.hospital_expire_flag,
        awa.hospital_los_days,
        CASE WHEN ckd.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ckd,
        CASE WHEN diab.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_diabetes
    FROM
        admissions_with_age_los AS awa
    INNER JOIN
        sepsis_icd_codes AS sepsis
        ON awa.hadm_id = sepsis.hadm_id
    LEFT JOIN
        septic_shock_icd_codes AS septic_shock
        ON awa.hadm_id = septic_shock.hadm_id
    LEFT JOIN
        ckd_icd_codes AS ckd
        ON awa.hadm_id = ckd.hadm_id
    LEFT JOIN
        diabetes_icd_codes AS diab
        ON awa.hadm_id = diab.hadm_id
    WHERE
        septic_shock.hadm_id IS NULL -- Exclude admissions with septic shock
),
processed_cohort AS (
    -- Determine ICU stay on Day 1 for each filtered admission
    SELECT
        fac.subject_id,
        fac.hadm_id,
        fac.hospital_expire_flag,
        fac.hospital_los_days,
        fac.has_ckd,
        fac.has_diabetes,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
                WHERE
                    icu.hadm_id = fac.hadm_id
                    AND icu.intime >= fac.admittime
                    AND icu.intime < DATETIME_ADD(fac.admittime, INTERVAL 1 DAY)
            ) THEN 'ICU on Day 1'
            ELSE 'Non-ICU on Day 1'
        END AS day1_icu_status
    FROM
        filtered_admissions_cohort AS fac
)
-- Final aggregation and reporting
SELECT
    CASE
        WHEN hospital_los_days <= 5 THEN 'LOS <= 5 days'
        ELSE 'LOS > 5 days'
    END AS hospital_los_group,
    day1_icu_status,
    COUNT(DISTINCT hadm_id) AS N,
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_percent,
    ROUND(AVG(has_ckd) * 100, 2) AS ckd_prevalence_percent,
    ROUND(AVG(has_diabetes) * 100, 2) AS diabetes_prevalence_percent
FROM
    processed_cohort
GROUP BY
    hospital_los_group,
    day1_icu_status
ORDER BY
    hospital_los_group,
    day1_icu_status;