with `OVER()`) are used together in the same `SELECT` statement without an explicit `GROUP BY` clause.

When you want to calculate global aggregate statistics (e.g., total count, min, max, percentiles) for the *entire* result set, and therefore expect a single output row, `PERCENTILE_CONT` should be used as a standard aggregate function without an `OVER()` clause. When `OVER()` is used without a `PARTITION BY` and without an explicit `ORDER BY` within the `OVER()` (though BigQuery's `PERCENTILE_CONT` for some reason implies ordering), BigQuery interprets it as a window function, and mixing these with other standard aggregates that implicitly operate on the whole set can lead to this specific error.

The fix involves removing the `OVER()` clause from all calls to `PERCENTILE_CONT`. When `PERCENTILE_CONT` is used without an `OVER()` clause in a `SELECT` statement that does not have a `GROUP BY` clause (and all other `SELECT` items are also aggregate functions returning a single value), it automatically acts as a global aggregate.

Key changes:
1.  **Removed `OVER()` clause from `PERCENTILE_CONT` functions**: This allows `PERCENTILE_CONT` to correctly perform as a global aggregate function alongside `COUNT`, `MIN`, `MAX`, and `SAFE_DIVIDE`, all of which are intended to produce a single row of summary statistics for the entire cohort.

sql
WITH pneumonia_admissions AS (
    -- 1. Identify admissions with a pneumonia diagnosis
    SELECT DISTINCT
        di.subject_id,
        di.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
        ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
    WHERE LOWER(did.long_title) LIKE '%pneumonia%'
),
cohort_base AS (
    -- 2. Filter for age, gender, and ensure an ICU stay for the admission
    SELECT DISTINCT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.deathtime,
        ad.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu                                  -- Join to icustays ensures an ICU stay
        ON ad.hadm_id = icu.hadm_id AND ad.subject_id = icu.subject_id                  -- Ensure patient and admission match on icustays
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 88 AND 98
        AND ad.hadm_id IN (SELECT hadm_id FROM pneumonia_admissions)
),
admission_diagnoses AS (
    -- Get detailed diagnosis information for the cohort, including AKI/ARDS flags and unique diagnosis count
    SELECT
        cb.subject_id,
        cb.hadm_id,
        cb.admittime,
        cb.deathtime,
        cb.hospital_expire_flag,
        -- Flag for Acute Kidney Injury (AKI)
        MAX(CASE
            WHEN (di.icd_version = 9 AND di.icd_code LIKE '584%')
                OR (di.icd_version = 10 AND di.icd_code LIKE 'N17%')
            THEN 1 ELSE 0
        END) AS has_aki,
        -- Flag for Acute Respiratory Distress Syndrome (ARDS)
        MAX(CASE
            WHEN (di.icd_version = 9 AND di.icd_code = '51882') -- 518.82 ARDS (ICD-9)
                OR (di.icd_version = 10 AND di.icd_code = 'J80') -- J80 ARDS (ICD-10)
            THEN 1 ELSE 0
        END) AS has_ards,
        -- Count unique non-pneumonia diagnoses for composite risk score (to avoid double counting pneumonia)
        COUNT(DISTINCT
            CASE WHEN NOT LOWER(did.long_title) LIKE '%pneumonia%' THEN di.icd_code ELSE NULL END
        ) AS num_unique_diagnoses
    FROM cohort_base cb
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON cb.subject_id = di.subject_id AND cb.hadm_id = di.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
        ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
    GROUP BY
        cb.subject_id, cb.hadm_id, cb.admittime, cb.deathtime, cb.hospital_expire_flag
),
admission_meds_labs AS (
    -- Get medication and lab data for composite risk score
    SELECT
        cb.hadm_id,
        COUNT(DISTINCT pr.drug) AS num_unique_meds,
        COUNT(DISTINCT dl.category) AS num_unique_lab_categories
    FROM cohort_base cb
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON cb.subject_id = pr.subject_id AND cb.hadm_id = pr.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON cb.subject_id = le.subject_id AND cb.hadm_id = le.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
        ON le.itemid = dl.itemid
    GROUP BY cb.hadm_id
),
final_cohort_data AS (
    -- Combine all calculated data for the final cohort
    SELECT
        adg.subject_id,
        adg.hadm_id,
        adg.admittime,
        adg.deathtime,
        adg.hospital_expire_flag,
        adg.has_aki,
        adg.has_ards,
        -- Simplified Composite Risk Score: (unique non-pneumonia diagnoses * 2) + (unique medications * 0.5) + (unique lab categories * 1)
        (adg.num_unique_diagnoses * 2)
        + (COALESCE(aml.num_unique_meds, 0) * 0.5)
        + (COALESCE(aml.num_unique_lab_categories, 0) * 1) AS composite_risk_score,
        DATE_DIFF(adg.deathtime, adg.admittime, DAY) AS survival_days
    FROM admission_diagnoses adg
    LEFT JOIN admission_meds_labs aml
        ON adg.hadm_id = aml.hadm_id
)
-- Final aggregation to answer the clinical question
SELECT
    COUNT(DISTINCT fcd.hadm_id) AS cohort_size,
    MIN(fcd.composite_risk_score) AS composite_risk_score_min,
    -- Percentiles for composite risk score distribution
    PERCENTILE_CONT(fcd.composite_risk_score, 0.25) AS composite_risk_score_25th_percentile,
    PERCENTILE_CONT(fcd.composite_risk_score, 0.5) AS composite_risk_score_median,
    PERCENTILE_CONT(fcd.composite_risk_score, 0.75) AS composite_risk_score_75th_percentile,
    MAX(fcd.composite_risk_score) AS composite_risk_score_max,
    SAFE_DIVIDE(COUNTIF(fcd.hospital_expire_flag = 1), COUNT(fcd.hadm_id)) * 100 AS in_hospital_mortality_rate_pct,
    SAFE_DIVIDE(COUNTIF(fcd.has_aki = 1), COUNT(fcd.hadm_id)) * 100 AS aki_rate_pct,
    SAFE_DIVIDE(COUNTIF(fcd.has_ards = 1), COUNT(fcd.hadm_id)) * 100 AS ards_rate_pct,
    -- Median survival days for decedents
    PERCENTILE_CONT(
        CASE WHEN fcd.hospital_expire_flag = 1 THEN fcd.survival_days ELSE NULL END, 0.5
    ) AS median_survival_days_for_decedents
FROM final_cohort<ctrl63>;