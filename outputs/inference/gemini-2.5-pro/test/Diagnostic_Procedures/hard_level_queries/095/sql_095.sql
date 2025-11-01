WITH first_icu_stays AS (
    -- Identify the first ICU stay for each hospital admission
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        intime,
        los,
        ROW_NUMBER() OVER(PARTITION BY hadm_id ORDER BY intime) as rn
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays`
),
pe_cohort_stays AS (
    -- Define the cohort of interest: male patients, aged 79-89, with a PE diagnosis, during their first ICU stay
    SELECT DISTINCT -- Use DISTINCT to avoid duplicates from multiple PE diagnosis codes for the same admission
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.los,
        adm.hospital_expire_flag
    FROM
        first_icu_stays AS icu
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat ON icu.subject_id = pat.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm ON icu.hadm_id = adm.hadm_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx ON icu.hadm_id = dx.hadm_id
    WHERE
        icu.rn = 1
        AND pat.gender = 'M'
        -- Calculate age at ICU admission and filter
        AND (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year + pat.anchor_age) BETWEEN 79 AND 89
        -- Filter for Pulmonary Embolism ICD-9 and ICD-10 codes
        AND (
            (dx.icd_version = 9 AND dx.icd_code LIKE '415.1%')
            OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I26.%')
        )
),
diagnostic_events AS (
    -- Collate diagnostic tests (labs and micro specimens) for the PE cohort in the first 24h
    -- Lab tests
    SELECT
        pcs.stay_id,
        le.itemid AS test_itemid
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN pe_cohort_stays AS pcs ON le.hadm_id = pcs.hadm_id
    WHERE
        le.charttime BETWEEN pcs.intime AND DATETIME_ADD(pcs.intime, INTERVAL 24 HOUR)

    UNION ALL

    -- Microbiology specimen tests
    SELECT
        pcs.stay_id,
        me.spec_itemid AS test_itemid
    FROM `physionet-data.mimiciv_3_1_hosp.microbiologyevents` AS me
    INNER JOIN pe_cohort_stays AS pcs ON me.hadm_id = pcs.hadm_id
    WHERE
        me.charttime IS NOT NULL
        AND me.charttime BETWEEN pcs.intime AND DATETIME_ADD(pcs.intime, INTERVAL 24 HOUR)
),
diag_scores AS (
    -- Calculate the diagnostic utilization score for each stay in the PE cohort
    SELECT
        stay_id,
        COUNT(DISTINCT test_itemid) AS diagnostic_score
    FROM
        diagnostic_events
    GROUP BY
        stay_id
),
pe_cohort_metrics AS (
    -- Calculate final metrics for the PE cohort
    SELECT
        APPROX_QUANTILES(COALESCE(ds.diagnostic_score, 0), 100)[OFFSET(75)] AS pe_cohort_p75_diagnostic_score,
        AVG(pcs.los) AS pe_cohort_avg_icu_los,
        AVG(CAST(pcs.hospital_expire_flag AS FLOAT64)) AS pe_cohort_in_hospital_mortality_rate
    FROM
        pe_cohort_stays AS pcs
    LEFT JOIN -- Use LEFT JOIN to include patients who may not have had any tests
        diag_scores AS ds ON pcs.stay_id = ds.stay_id
),
general_pop_metrics AS (
    -- Calculate metrics for the general ICU population (first ICU stays)
    SELECT
        AVG(icu.los) AS general_pop_avg_icu_los,
        AVG(CAST(adm.hospital_expire_flag AS FLOAT64)) AS general_pop_in_hospital_mortality_rate
    FROM
        first_icu_stays AS icu
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm ON icu.hadm_id = adm.hadm_id
    WHERE
        icu.rn = 1
)
-- Final result combining metrics from both groups for comparison
SELECT
    pe.pe_cohort_p75_diagnostic_score,
    pe.pe_cohort_avg_icu_los,
    pe.pe_cohort_in_hospital_mortality_rate,
    gp.general_pop_avg_icu_los,
    gp.general_pop_in_hospital_mortality_rate
FROM
    pe_cohort_metrics AS pe
CROSS JOIN
    general_pop_metrics AS gp;