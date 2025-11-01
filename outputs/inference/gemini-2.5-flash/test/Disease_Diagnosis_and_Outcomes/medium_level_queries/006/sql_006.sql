WITH base_cohort AS (
    -- Step 1: Create a base cohort of admissions with age, gender, and LOS (in days)
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.hospital_expire_flag,
        pa.gender,
        pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year) AS age_at_admission,
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'M'
),
diagnoses_flags AS (
    -- Step 2: Identify relevant diagnoses for each admission
    SELECT
        di.subject_id,
        di.hadm_id,
        MAX(CASE WHEN di.icd_version = 10 AND (
            STARTS_WITH(di.icd_code, 'A40') OR STARTS_WITH(di.icd_code, 'A41')
        ) THEN 1 ELSE 0 END) AS has_sepsis,
        MAX(CASE WHEN di.icd_version = 10 AND di.icd_code = 'R6521' THEN 1 ELSE 0 END) AS has_septic_shock,
        MAX(CASE WHEN di.icd_version = 10 AND STARTS_WITH(di.icd_code, 'N18') THEN 1 ELSE 0 END) AS has_ckd,
        MAX(CASE WHEN di.icd_version = 10 AND (
            STARTS_WITH(di.icd_code, 'E10') OR STARTS_WITH(di.icd_code, 'E11') OR STARTS_WITH(di.icd_code, 'E13')
        ) THEN 1 ELSE 0 END) AS has_diabetes
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    GROUP BY
        di.subject_id, di.hadm_id
),
filtered_cohort AS (
    -- Step 3: Apply initial age, sepsis, septic shock, and LOS filters
    SELECT
        bc.subject_id,
        bc.hadm_id,
        bc.hospital_expire_flag,
        bc.los_days,
        df.has_ckd,
        df.has_diabetes
    FROM
        base_cohort AS bc
    INNER JOIN
        diagnoses_flags AS df
        ON bc.subject_id = df.subject_id AND bc.hadm_id = df.hadm_id
    WHERE
        bc.age_at_admission BETWEEN 64 AND 74
        AND df.has_sepsis = 1
        AND df.has_septic_shock = 0
        AND bc.los_days IS NOT NULL -- Exclude admissions with null LOS
        AND bc.los_days >= 0 -- Ensure positive LOS
),
cohort_with_quartiles AS (
    -- Step 4: Calculate LOS quartiles for the filtered cohort
    SELECT
        subject_id,
        hadm_id,
        hospital_expire_flag,
        los_days,
        has_ckd,
        has_diabetes,
        -- Assign patients to LOS quartiles (Q1-Q4)
        NTILE(4) OVER (ORDER BY los_days) AS los_quartile
    FROM
        filtered_cohort
)
-- Final Step: Calculate in-hospital mortality rates and CKD/diabetes prevalence by LOS quartile
SELECT
    los_quartile,
    COUNT(DISTINCT hadm_id) AS total_admissions,
    SUM(hospital_expire_flag) AS in_hospital_deaths,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(DISTINCT hadm_id)) * 100 AS mortality_rate_percent,
    SUM(has_ckd) AS admissions_with_ckd,
    SAFE_DIVIDE(SUM(has_ckd), COUNT(DISTINCT hadm_id)) * 100 AS ckd_prevalence_percent,
    SUM(has_diabetes) AS admissions_with_diabetes,
    SAFE_DIVIDE(SUM(has_diabetes), COUNT(DISTINCT hadm_id)) * 100 AS diabetes_prevalence_percent
FROM
    cohort_with_quartiles
GROUP BY
    los_quartile
ORDER BY
    los_quartile;