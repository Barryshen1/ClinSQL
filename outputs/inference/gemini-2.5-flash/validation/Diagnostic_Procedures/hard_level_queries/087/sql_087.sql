WITH ich_admissions AS (
    SELECT
        DISTINCT ha.subject_id,
        ha.hadm_id,
        ha.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ha
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` hp
        ON ha.subject_id = hp.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ha.hadm_id = di.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu_check -- Join to ensure the admission had an ICU stay
        ON ha.hadm_id = icu_check.hadm_id
    WHERE
        hp.gender = 'F'
        AND hp.anchor_age BETWEEN 56 AND 66
        AND di.icd_version = 10 -- MIMIC-IV primarily uses ICD-10 for recent data.
        AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%')
),
-- CTE 2: Calculate diagnostic intensity (count of distinct lab itemids)
-- for the first 72 hours of *each and every* ICU stay in the database.
icu_stay_lab_intensity AS (
    SELECT
        icu.stay_id,
        COUNT(DISTINCT le.itemid) AS diagnostic_intensity_72hr
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` icu
    LEFT JOIN -- Use LEFT JOIN to include all ICU stays, even if they have no unique labs in 72h
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON icu.subject_id = le.subject_id
        AND icu.hadm_id = le.hadm_id
        AND le.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
    GROUP BY
        icu.stay_id
),
-- CTE 3: Prepare comprehensive data for the ICH cohort's ICU stays.
-- This includes LOS, mortality, and the calculated diagnostic intensity.
ich_cohort_data AS (
    SELECT
        ia.subject_id,
        ia.hadm_id,
        ia.hospital_expire_flag,
        icu.stay_id,
        icu.los AS icu_los_days,
        COALESCE(isi.diagnostic_intensity_72hr, 0) AS diagnostic_intensity_72hr
    FROM
        ich_admissions ia
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON ia.hadm_id = icu.hadm_id
    LEFT JOIN
        icu_stay_lab_intensity isi
        ON icu.stay_id = isi.stay_id
),
-- CTE 4: Prepare comprehensive data for the Overall ICU population.
-- This includes LOS, mortality, and the calculated diagnostic intensity for every ICU stay.
overall_icu_data AS (
    SELECT
        icu.subject_id,
        icu.hadm_id,
        adm.hospital_expire_flag,
        icu.stay_id,
        icu.los AS icu_los_days,
        COALESCE(isi.diagnostic_intensity_72hr, 0) AS diagnostic_intensity_72hr
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON icu.hadm_id = adm.hadm_id
    LEFT JOIN
        icu_stay_lab_intensity isi
        ON icu.stay_id = isi.stay_id
),
-- New CTE: Calculate the 95th percentile of diagnostic intensity for the ICH Cohort
ich_cohort_pctl AS (
    SELECT
        APPROX_QUANTILES(diagnostic_intensity_72hr, 100)[OFFSET(95)] AS p95_diagnostic_intensity_72hr
    FROM
        ich_cohort_data
),
-- New CTE: Calculate the 95th percentile of diagnostic intensity for the Overall ICU Population
overall_icu_pctl AS (
    SELECT
        APPROX_QUANTILES(diagnostic_intensity_72hr, 100)[OFFSET(95)] AS p95_diagnostic_intensity_72hr
    FROM
        overall_icu_data
)
-- Final aggregation to calculate the requested statistics for the ICH Cohort.
SELECT
    'ICH Cohort (Female, 56-66, ICH)' AS cohort_name,
    (SELECT p95_diagnostic_intensity_72hr FROM ich_cohort_pctl) AS p95_diagnostic_intensity_72hr,
    AVG(icu_los_days) * 24 AS avg_icu_los_hours,
    (COUNT(DISTINCT CASE WHEN hospital_expire_flag = 1 THEN hadm_id END) * 100.0 / COUNT(DISTINCT hadm_id)) AS in_hospital_mortality_rate_percent
FROM
    ich_cohort_data

UNION ALL

-- Final aggregation to calculate the requested statistics for the Overall ICU Population.
SELECT
    'Overall ICU Population' AS cohort_name,
    (SELECT p95_diagnostic_intensity_72hr FROM overall_icu_pctl) AS p95_diagnostic_intensity_72hr,
    AVG(icu_los_days) * 24 AS avg_icu_los_hours,
    (COUNT(DISTINCT CASE WHEN hospital_expire_flag = 1 THEN hadm_id END) * 100.0 / COUNT(DISTINCT hadm_id)) AS in_hospital_mortality_rate_percent
FROM
    overall_icu_data

ORDER BY
    cohort_name;