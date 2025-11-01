WITH cohort AS (
    -- Step 1: Identify the base cohort of male patients aged 51-61
    SELECT
        ad.hadm_id,
        ad.hospital_expire_flag,
        -- Calculate hospital length of stay in days.
        -- Using CEIL ensures a minimum of 1 day for any admission.
        GREATEST(1, CEIL(DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) / 24.0)) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'M'
        -- Calculate age at admission and filter
        AND (
            pa.anchor_age + DATETIME_DIFF(ad.admittime, DATETIME(pa.anchor_year, 1, 1, 0, 0, 0), YEAR)
        ) BETWEEN 51 AND 61
),
diagnoses_agg AS (
    -- Step 2: Flag diagnoses for MI and comorbidities for each admission in the cohort
    SELECT
        dx.hadm_id,
        -- Flag for STEMI
        MAX(CASE
            WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) = '410' AND SUBSTR(dx.icd_code, 4, 1) != '7')
              OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 4) IN ('I210', 'I211', 'I212', 'I213'))
            THEN 1 ELSE 0 END) AS is_stemi,
        -- Flag for NSTEMI
        MAX(CASE
            WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 4) = '4107')
              OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 4) = 'I214')
            THEN 1 ELSE 0 END) AS is_nstemi,
        -- Flag for Diabetes
        MAX(CASE
            WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) = '250')
              OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN 'E08' AND 'E13')
            THEN 1 ELSE 0 END) AS has_diabetes,
        -- Flag for Chronic Kidney Disease (CKD)
        MAX(CASE
            WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) = '585')
              OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) IN ('N18', 'I12', 'I13'))
            THEN 1 ELSE 0 END) AS has_ckd,
        -- Flag for Congestive Heart Failure (CHF) for comorbidity count
        MAX(CASE
            WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) = '428')
              OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) = 'I50')
            THEN 1 ELSE 0 END) AS has_chf,
        -- Flag for Chronic Pulmonary Disease (COPD) for comorbidity count
        MAX(CASE
            WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN '490' AND '496')
              OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN 'J40' AND 'J47')
            THEN 1 ELSE 0 END) AS has_copd,
        -- Flag for Liver Disease for comorbidity count
        MAX(CASE
            WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) = '571')
              OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) IN ('K70', 'K74'))
            THEN 1 ELSE 0 END) AS has_liver_dz,
        -- Flag for Cancer for comorbidity count (excluding non-melanoma skin cancer)
        MAX(CASE
            WHEN (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN '140' AND '208' AND SUBSTR(dx.icd_code, 1, 3) != '173')
              OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 1) = 'C' AND SUBSTR(dx.icd_code, 1, 3) != 'C44')
            THEN 1 ELSE 0 END) AS has_cancer
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    INNER JOIN cohort ON dx.hadm_id = cohort.hadm_id
    GROUP BY dx.hadm_id
),
final_data AS (
    -- Step 3: Combine cohort with diagnoses, filter for MI patients, and create reporting groups
    SELECT
        c.hadm_id,
        c.hospital_expire_flag,
        d.has_ckd,
        d.has_diabetes,
        -- Assign MI type, prioritizing STEMI
        CASE WHEN d.is_stemi = 1 THEN 'STEMI' ELSE 'NSTEMI' END AS mi_type,
        -- Create LOS groups
        CASE
            WHEN c.los_days BETWEEN 1 AND 2 THEN '1-2 days'
            WHEN c.los_days BETWEEN 3 AND 5 THEN '3-5 days'
            WHEN c.los_days BETWEEN 6 AND 9 THEN '6-9 days'
            WHEN c.los_days >= 10 THEN '>=10 days'
        END AS los_group,
        -- Sum flags to get comorbidity count and create groups
        CASE
            WHEN (d.has_diabetes + d.has_ckd + d.has_chf + d.has_copd + d.has_liver_dz + d.has_cancer) <= 1 THEN '0-1'
            WHEN (d.has_diabetes + d.has_ckd + d.has_chf + d.has_copd + d.has_liver_dz + d.has_cancer) = 2 THEN '2'
            WHEN (d.has_diabetes + d.has_ckd + d.has_chf + d.has_copd + d.has_liver_dz + d.has_cancer) >= 3 THEN '>=3'
        END AS comorbidity_group
    FROM cohort AS c
    INNER JOIN diagnoses_agg AS d
        ON c.hadm_id = d.hadm_id
    -- Filter for admissions that are either STEMI or NSTEMI
    WHERE
        d.is_stemi = 1 OR d.is_nstemi = 1
)
-- Step 4: Final aggregation and calculation of metrics
SELECT
    mi_type,
    los_group,
    comorbidity_group,
    COUNT(hadm_id) AS N,
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
    ROUND(AVG(has_ckd) * 100, 2) AS ckd_prevalence_pct,
    ROUND(AVG(has_diabetes) * 100, 2) AS diabetes_prevalence_pct
FROM
    final_data
WHERE
    los_group IS NOT NULL AND comorbidity_group IS NOT NULL
GROUP BY
    mi_type, los_group, comorbidity_group
ORDER BY
    mi_type,
    -- Custom sort order for LOS and comorbidity groups
    CASE los_group
        WHEN '1-2 days' THEN 1
        WHEN '3-5 days' THEN 2
        WHEN '6-9 days' THEN 3
        WHEN '>=10 days' THEN 4
    END,
    CASE comorbidity_group
        WHEN '0-1' THEN 1
        WHEN '2' THEN 2
        WHEN '>=3' THEN 3
    END;