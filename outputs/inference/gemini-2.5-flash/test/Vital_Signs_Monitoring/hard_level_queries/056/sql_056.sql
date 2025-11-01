WITH cohort AS (
    -- Step 1: Identify the patient cohort (Male, 74-84, Hemorrhagic Stroke, ICU stay)
    SELECT
        p.subject_id,
        adm.hadm_id,
        icu.stay_id,
        p.gender,
        p.anchor_age,
        icu.intime,
        icu.outtime,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
            ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
            ON adm.hadm_id = icu.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 74 AND 84
        -- Filter for hemorrhagic stroke diagnosis (ICD-10 codes I60% or I61%)
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE
                di.hadm_id = adm.hadm_id
                AND di.icd_version = 10 -- Focus on ICD-10 for MIMIC-IV
                AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%')
        )
),
raw_vitals AS (
    -- Step 2: Extract relevant vital signs and bin by hour for the first 48 hours in ICU
    SELECT
        c.subject_id,
        c.hadm_id,
        c.stay_id,
        c.intime,
        c.outtime,
        DATETIME_TRUNC(ce.charttime, HOUR) AS chart_hour,
        c.hospital_expire_flag, -- Carry forward for mortality calculation
        -- Flag an hour if temperature > 38.5C (itemid 223762 is Temperature C)
        MAX(CASE WHEN ce.itemid = 223762 AND ce.valuenum > 38.5 THEN 1 ELSE 0 END) AS fever_event,
        -- Flag an hour if SpO2 < 90% (itemid 220277 is SpO2)
        MAX(CASE WHEN ce.itemid = 220277 AND ce.valuenum < 90 AND ce.valuenum IS NOT NULL THEN 1 ELSE 0 END) AS hypoxemia_event,
        -- Flag an hour if Respiratory Rate > 20 (itemid 220210 is Respiratory Rate)
        MAX(CASE WHEN ce.itemid = 220210 AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS tachypnea_event
    FROM
        cohort c
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.subject_id = ce.subject_id
        AND c.stay_id = ce.stay_id
    WHERE
        ce.itemid IN (223762, 220277, 220210) -- Filter for relevant vital sign itemids
        AND ce.valuenum IS NOT NULL -- Exclude null values for numeric comparison
        AND ce.charttime >= c.intime
        AND ce.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR) -- First 48 hours of ICU stay
    GROUP BY
        c.subject_id, c.hadm_id, c.stay_id, c.intime, c.outtime, c.hospital_expire_flag, DATETIME_TRUNC(ce.charttime, HOUR)
),
instability_summary AS (
    -- Step 3: Summarize instability hours per ICU stay
    SELECT
        rv.subject_id,
        rv.hadm_id,
        rv.stay_id,
        rv.intime,
        rv.outtime,
        MAX(rv.hospital_expire_flag) AS hospital_expire_flag,
        COUNT(DISTINCT CASE WHEN rv.fever_event = 1 OR rv.hypoxemia_event = 1 OR rv.tachypnea_event = 1 THEN rv.chart_hour END) AS total_instability_hours,
        COUNT(DISTINCT CASE WHEN rv.fever_event = 1 THEN rv.chart_hour END) AS fever_hours,
        COUNT(DISTINCT CASE WHEN rv.hypoxemia_event = 1 THEN rv.chart_hour END) AS hypoxemia_hours,
        COUNT(DISTINCT CASE WHEN rv.tachypnea_event = 1 THEN rv.chart_hour END) AS tachypnea_hours
    FROM
        raw_vitals rv
    GROUP BY
        rv.subject_id, rv.hadm_id, rv.stay_id, rv.intime, rv.outtime
),
p90_threshold AS (
    -- Step 4: Calculate the 90th percentile of total instability hours once
    SELECT
        PERCENTILE_CONT(total_instability_hours, 0.9) OVER () AS p90_instability_hours
    FROM
        instability_summary
    LIMIT 1 -- Only need one row with the percentile value
)
-- Step 5: Report 90th percentile and top decile metrics
SELECT
    (SELECT p90_instability_hours FROM p90_threshold) AS percentile_90th_instability_hours,
    COUNT(s.stay_id) AS num_patients_top_decile,
    AVG(TIMESTAMP_DIFF(s.outtime, s.intime, HOUR) / 24.0) AS mean_icu_los_top_decile_days,
    ROUND(SUM(s.hospital_expire_flag) * 100.0 / COUNT(s.stay_id), 2) AS mortality_percent_top_decile,
    AVG(s.fever_hours) AS mean_fever_hours_top_decile,
    AVG(s.hypoxemia_hours) AS mean_hypoxemia_hours_top_decile,
    AVG(s.tachypnea_hours) AS mean_tachypnea_hours_top_decile
FROM
    instability_summary s
WHERE
    s.total_instability_hours >= (SELECT p90_instability_hours FROM p90_threshold);