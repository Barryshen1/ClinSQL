WITH
    admissions_with_age AS (
        -- Calculate age at admission for each patient
        SELECT
            adm.subject_id,
            adm.hadm_id,
            adm.admittime,
            adm.dischtime,
            adm.deathtime,
            adm.hospital_expire_flag,
            pat.gender,
            -- Calculate age at admission: anchor_age + (admission year - anchor_year)
            pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
            ON adm.subject_id = pat.subject_id
    ),
    hf_admissions_cohort AS (
        -- Identify the cohort: female inpatients, aged 59-69, with Heart Failure (HF) diagnosis
        SELECT DISTINCT
            a.subject_id,
            a.hadm_id,
            a.admittime,
            a.dischtime,
            a.deathtime,
            a.hospital_expire_flag,
            a.age_at_admission
        FROM admissions_with_age AS a
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
            ON a.hadm_id = di.hadm_id
        WHERE
            a.gender = 'F'
            AND a.age_at_admission BETWEEN 59 AND 69
            AND (
                -- ICD-10 codes for Heart Failure (I50)
                (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
                -- ICD-9 codes for Heart Failure (428)
                OR (di.icd_version = 9 AND di.icd_code LIKE '428%')
            )
    ),
    aki_ards_flags AS (
        -- Determine if each admission in the cohort had AKI or ARDS diagnosis
        SELECT
            hf.hadm_id,
            MAX(
                CASE
                    -- ICD-10 codes for Acute Kidney Injury (N17)
                    WHEN (di.icd_version = 10 AND di.icd_code LIKE 'N17%')
                    -- ICD-9 codes for Acute Kidney Injury (584)
                    OR (di.icd_version = 9 AND di.icd_code LIKE '584%')
                    THEN 1
                    ELSE 0
                END
            ) AS has_aki,
            MAX(
                CASE
                    -- ICD-10 code for Acute Respiratory Distress Syndrome (J80)
                    WHEN (di.icd_version = 10 AND di.icd_code = 'J80')
                    -- ICD-9 code for Acute Respiratory Distress Syndrome (51882)
                    OR (di.icd_version = 9 AND di.icd_code = '51882')
                    THEN 1
                    ELSE 0
                END
            ) AS has_ards
        FROM hf_admissions_cohort AS hf
        LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
            ON hf.hadm_id = di.hadm_id
        GROUP BY
            hf.hadm_id
    ),
    composite_risk_scores AS (
        -- Calculate a "composite risk score" as the count of distinct ICD diagnoses for each admission.
        -- This serves as a proxy for patient complexity or burden of illness.
        SELECT
            hf.hadm_id,
            COUNT(DISTINCT di.icd_code) AS distinct_diagnosis_count
        FROM hf_admissions_cohort AS hf
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
            ON hf.hadm_id = di.hadm_id
        GROUP BY
            hf.hadm_id
    ),
    final_cohort_data AS (
        -- Consolidate all relevant data for the cohort into a single CTE
        SELECT
            hf.hadm_id,
            hf.hospital_expire_flag,
            hf.admittime,
            hf.deathtime,
            COALESCE(flags.has_aki, 0) AS has_aki, -- Default to 0 if no AKI diagnosis found
            COALESCE(flags.has_ards, 0) AS has_ards, -- Default to 0 if no ARDS diagnosis found
            COALESCE(crs.distinct_diagnosis_count, 0) AS composite_risk_score, -- Default to 0 if no diagnoses found (unlikely for HF cohort)
            DATETIME_DIFF(hf.deathtime, hf.admittime, HOUR) AS survival_duration_hours_if_death -- NULL for patients who did not die in-hospital
        FROM hf_admissions_cohort AS hf
        LEFT JOIN aki_ards_flags AS flags
            ON hf.hadm_id = flags.hadm_id
        LEFT JOIN composite_risk_scores AS crs
            ON hf.hadm_id = crs.hadm_id
    )
SELECT
    -- In-hospital mortality rate (percentage of patients who died during hospitalization)
    (SUM(CASE WHEN fcd.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(fcd.hadm_id)) AS in_hospital_mortality_rate_percent,

    -- AKI rate (percentage of patients diagnosed with AKI)
    (SUM(fcd.has_aki) * 100.0 / COUNT(fcd.hadm_id)) AS aki_rate_percent,

    -- ARDS rate (percentage of patients diagnosed with ARDS)
    (SUM(fcd.has_ards) * 100.0 / COUNT(fcd.hadm_id)) AS ards_rate_percent,

    -- Median survival duration among patients who died in-hospital (in hours)
    -- Use BigQuery's APPROX_QUANTILES to estimate the median. It ignores NULLs.
    APPROX_QUANTILES(fcd.survival_duration_hours_if_death, 2)[OFFSET(1)] AS median_survival_duration_hours_among_deaths,

    -- Composite risk score distribution (min, percentiles, max)
    MIN(fcd.composite_risk_score) AS risk_score_min,
    APPROX_QUANTILES(fcd.composite_risk_score, 4)[OFFSET(1)] AS risk_score_p25, -- 1st quartile (25th percentile)
    APPROX_QUANTILES(fcd.composite_risk_score, 2)[OFFSET(1)] AS risk_score_median, -- 2nd quartile (50th percentile/median)
    APPROX_QUANTILES(fcd.composite_risk_score, 4)[OFFSET(3)] AS risk_score_p75, -- 3rd quartile (75th percentile)
    APPROX_QUANTILES(fcd.composite_risk_score, 10)[OFFSET(9)] AS risk_score_p90, -- 9th decile (90th percentile)
    MAX(fcd.composite_risk_score) AS risk_score_max
FROM final_cohort_data AS fcd;