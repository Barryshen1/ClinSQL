with status epilepticus.
It calculates a vital-instability index and other metrics for their first 72 hours,
and compares these metrics to a general ICU population.
*/
WITH se_diagnoses AS (
    -- Find all hospital admissions with a diagnosis of status epilepticus
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 9 AND icd_code = '3453') -- ICD-9 for Status epilepticus
        OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'G41') -- ICD-10 for Status epilepticus
),

se_cohort AS (
    -- Define the case cohort (Status Epilepticus patients) and control (General ICU)
    SELECT
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        -- The case group: Female, 63-73 yo, with a status epilepticus diagnosis
        CASE
            WHEN
                p.gender = 'F'
                AND (p.anchor_age + EXTRACT(YEAR FROM icu.intime) - p.anchor_year) BETWEEN 63 AND 73
                AND se.hadm_id IS NOT NULL
                THEN TRUE
            ELSE FALSE
        END AS is_se_patient
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON icu.subject_id = p.subject_id
    LEFT JOIN se_diagnoses AS se
        ON icu.hadm_id = se.hadm_id
),

vitals_first_72h AS (
    -- Extract relevant vital signs from the first 72 hours of each ICU stay
    SELECT
        c.stay_id,
        ce.charttime,
        ce.itemid,
        ce.valuenum
    FROM se_cohort AS c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        ON c.stay_id = ce.stay_id
    WHERE
        ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
        AND ce.itemid IN (
            220045, -- Heart Rate
            220181, -- Non Invasive Blood Pressure mean
            220052, -- Arterial Blood Pressure mean
            220277, -- O2 saturation pulseoxymetry
            220210, -- Respiratory Rate
            223762, -- Temperature Celsius
            223761  -- Temperature Fahrenheit
        )
        AND ce.valuenum IS NOT NULL AND ce.valuenum > 0
),

vitals_pivoted AS (
    -- Pivot the vitals data to have one row per timestamp with vitals in columns
    SELECT
        stay_id,
        charttime,
        MAX(CASE WHEN itemid = 220045 THEN valuenum END) AS hr,
        COALESCE(
            MAX(CASE WHEN itemid = 220052 THEN valuenum END),
            MAX(CASE WHEN itemid = 220181 THEN valuenum END)
        ) AS map,
        MAX(CASE WHEN itemid = 220277 THEN valuenum END) AS spo2,
        MAX(CASE WHEN itemid = 220210 THEN valuenum END) AS rr,
        COALESCE(
            MAX(CASE WHEN itemid = 223762 THEN valuenum END),
            MAX(CASE WHEN itemid = 223761 THEN (valuenum - 32) * 5 / 9 END)
        ) AS temp_c
    FROM vitals_first_72h
    GROUP BY stay_id, charttime
),

instability_metrics AS (
    -- Calculate the Vital-Instability Index (VII) and flags for other burdens
    SELECT
        stay_id,
        -- Vital-Instability Index: count of abnormal vitals (range 0-5)
        (
            (CASE WHEN hr < 60 OR hr > 100 THEN 1 ELSE 0 END)
            + (CASE WHEN map < 65 THEN 1 ELSE 0 END)
            + (CASE WHEN spo2 < 92 THEN 1 ELSE 0 END)
            + (CASE WHEN rr < 12 OR rr > 20 THEN 1 ELSE 0 END)
            + (CASE WHEN temp_c < 36.0 OR temp_c > 38.0 THEN 1 ELSE 0 END)
        ) AS vii,
        -- Flags for burdens
        CASE WHEN hr > 100 THEN 1 ELSE 0 END AS is_tachycardic,
        CASE WHEN map < 65 THEN 1 ELSE 0 END AS is_hypotensive_map
    FROM vitals_pivoted
),

stay_level_metrics AS (
    -- Aggregate the instability metrics to the stay level (one row per stay_id)
    SELECT
        stay_id,
        AVG(vii) AS avg_vii,
        AVG(is_tachycardic) AS tachycardia_burden,
        AVG(is_hypotensive_map) AS map_lt_65_burden
    FROM instability_metrics
    GROUP BY stay_id
)

-- Final aggregation and comparison of the two cohorts
SELECT
    CASE
        WHEN c.is_se_patient THEN 'Status Epilepticus Cohort'
        ELSE 'General ICU Cohort'
    END AS patient_group,
    COUNT(DISTINCT c.stay_id) AS number_of_stays,

    -- Vital-Instability Index statistics
    AVG(slm.avg_vii) AS mean_vital_instability_index,
    APPROX_QUANTILES(slm.avg_vii, 100)[OFFSET(25)] AS vii_p25,
    APPROX_QUANTILES(slm.avg_vii, 100)[OFFSET(50)] AS vii_p50_median,
    APPROX_QUANTILES(slm.avg_vii, 100)[OFFSET(75)] AS vii_p75,
    APPROX_QUANTILES(slm.avg_vii, 100)[OFFSET(90)] AS vii_p90,

    -- Other outcome metrics
    AVG(slm.tachycardia_burden) AS mean_tachycardia_burden,
    AVG(slm.map_lt_65_burden) AS mean_map_lt_65_burden,
    AVG(icu.los) AS mean_icu_los_days,
    AVG(CAST(adm.hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate

FROM se_cohort AS c
LEFT JOIN stay_level_metrics AS slm
    ON c.stay_id = slm.stay_id
LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON c.stay_id = icu.stay_id
LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON c.hadm_id = adm.hadm_id
GROUP BY patient_group
ORDER BY patient_group DESC;