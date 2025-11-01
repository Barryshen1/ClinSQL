WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag AS mortality,
        DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE 
        p.anchor_age BETWEEN 48 AND 58
        AND p.gender = 'M'
        AND d.icd_code LIKE 'J18%'
        AND d.icd_version = 10
),

meds_first_24h AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        COUNT(DISTINCT e.medication) AS num_meds
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
        ON c.hadm_id = e.hadm_id
        AND e.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
    GROUP BY c.subject_id, c.hadm_id
),

serotonergic_meds AS (
    SELECT DISTINCT
        c.subject_id,
        c.hadm_id,
        1 AS has_serotonergic
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
        ON c.hadm_id = e.hadm_id
        AND e.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
    WHERE 
        LOWER(e.medication) LIKE '%citalopram%'
        OR LOWER(e.medication) LIKE '%escitalopram%'
        OR LOWER(e.medication) LIKE '%fluoxetine%'
        OR LOWER(e.medication) LIKE '%fluvoxamine%'
        OR LOWER(e.medication) LIKE '%paroxetine%'
        OR LOWER(e.medication) LIKE '%sertraline%'
        OR LOWER(e.medication) LIKE '%venlafaxine%'
        OR LOWER(e.medication) LIKE '%duloxetine%'
        OR LOWER(e.medication) LIKE '%tramadol%'
        OR LOWER(e.medication) LIKE '%triptan%'
        OR LOWER(e.medication) LIKE '%sumatriptan%'
),

icu_patients AS (
    SELECT DISTINCT
        c.subject_id,
        c.hadm_id,
        1 AS in_icu
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON c.hadm_id = i.hadm_id
),

combined_data AS (
    SELECT 
        c.*,
        COALESCE(m.num_meds, 0) AS num_meds,
        COALESCE(s.has_serotonergic, 0) AS has_serotonergic,
        COALESCE(i.in_icu, 0) AS in_icu
    FROM cohort c
    LEFT JOIN meds_first_24h m
        ON c.hadm_id = m.hadm_id
    LEFT JOIN serotonergic_meds s
        ON c.hadm_id = s.hadm_id
    LEFT JOIN icu_patients i
        ON c.hadm_id = i.hadm_id
)

-- Medication complexity distribution
SELECT 
    'Medication Complexity' AS metric,
    COUNT(*) AS n,
    AVG(num_meds) AS mean,
    APPROX_QUANTILES(num_meds, 4)[OFFSET(1)] AS p25,
    APPROX_QUANTILES(num_meds, 4)[OFFSET(2)] AS p50,
    APPROX_QUANTILES(num_meds, 4)[OFFSET(3)] AS p75
FROM combined_data

UNION ALL

-- Compare serotonergic vs non-serotonergic
SELECT 
    'Serotonergic Risk: LOS' AS metric,
    COUNT(*) AS n,
    AVG(los_days) AS mean,
    APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS p25,
    APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS p50,
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS p75
FROM combined_data
WHERE has_serotonergic = 1

UNION ALL

SELECT 
    'Non-Serotonergic Risk: LOS' AS metric,
    COUNT(*) AS n,
    AVG(los_days) AS mean,
    APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS p25,
    APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS p50,
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS p75
FROM combined_data
WHERE has_serotonergic = 0

UNION ALL

SELECT 
    'Serotonergic Risk: Mortality' AS metric,
    COUNT(*) AS n,
    AVG(mortality) AS mortality_rate,
    NULL AS p25,
    NULL AS p50,
    NULL AS p75
FROM combined_data
WHERE has_serotonergic = 1

UNION ALL

SELECT 
    'Non-Serotonergic Risk: Mortality' AS metric,
    COUNT(*) AS n,
    AVG(mortality) AS mortality_rate,
    NULL AS p25,
    NULL AS p50,
    NULL AS p75
FROM combined_data
WHERE has_serotonergic = 0

UNION ALL

-- Compare ICU vs non-ICU
SELECT 
    'ICU Patients: LOS' AS metric,
    COUNT(*) AS n,
    AVG(los_days) AS mean,
    APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS p25,
    APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS p50,
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS p75
FROM combined_data
WHERE in_icu = 1

UNION ALL

SELECT 
    'Non-ICU Patients: LOS' AS metric,
    COUNT(*) AS n,
    AVG(los_days) AS mean,
    APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS p25,
    APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS p50,
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS p75
FROM combined_data
WHERE in_icu = 0

UNION ALL

SELECT 
    'ICU Patients: Mortality' AS metric,
    COUNT(*) AS n,
    AVG(mortality) AS mortality_rate,
    NULL AS p25,
    NULL AS p50,
    NULL AS p75
FROM combined_data
WHERE in_icu = 1

UNION ALL

SELECT 
    'Non-ICU Patients: Mortality' AS metric,
    COUNT(*) AS n,
    AVG(mortality) AS mortality_rate,
    NULL AS p25,
    NULL AS p50,
    NULL AS p75
FROM combined_data
WHERE in_icu = 0

UNION ALL

-- Top quartile complexity: LOS and mortality
SELECT 
    'Top Quartile Complexity: LOS' AS metric,
    COUNT(*) AS n,
    AVG(los_days) AS mean,
    APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS p25,
    APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS p50,
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS p75
FROM combined_data
WHERE num_meds >= (SELECT APPROX_QUANTILES(num_meds, 4)[OFFSET(3)] FROM combined_data)

UNION ALL

SELECT 
    'Top Quartile Complexity: Mortality' AS metric,
    COUNT(*) AS n,
    AVG(mortality) AS mortality_rate,
    NULL AS p25,
    NULL AS p50,
    NULL AS p75
FROM combined_data
WHERE num_meds >= (SELECT APPROX_QUANTILES(num_meds, 4)[OFFSET(3)] FROM combined_data)
;