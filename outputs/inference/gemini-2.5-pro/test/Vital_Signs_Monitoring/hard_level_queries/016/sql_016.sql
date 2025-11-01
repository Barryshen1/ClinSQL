WITH transplant_patients AS (
    SELECT DISTINCT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 codes for transplant status or complications
        SUBSTR(icd_code, 1, 3) IN ('V42', '996')
        OR icd_code LIKE '996.8%'
        -- ICD-10 codes for transplant status or complications
        OR SUBSTR(icd_code, 1, 3) IN ('Z94', 'T86')
),

-- CTE 2: Identify the base cohort of ICU stays for male patients aged 57-67
-- and classify them into Transplant/Non-Transplant cohorts.
base_stays AS (
    SELECT
        p.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.los,
        CASE
            WHEN tp.subject_id IS NOT NULL THEN 'Transplant'
            ELSE 'Non-Transplant'
        END AS cohort
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON icu.subject_id = p.subject_id
    LEFT JOIN transplant_patients AS tp
        ON p.subject_id = tp.subject_id
    WHERE
        p.gender = 'M'
        -- Use anchor_age as a proxy for age at admission
        AND p.anchor_age BETWEEN 57 AND 67
),

-- CTE 3: Identify all instability events (fever, hypoxemia, tachypnea)
-- in the first 72 hours for the base cohort.
instability_events AS (
    SELECT
        ce.stay_id,
        -- Count of individual measurements that are abnormal
        (CASE
            -- Fever: Temp > 38.5 C
            WHEN ce.itemid = 223762 AND ce.valuenum > 38.5 THEN 1 -- Temp C
            WHEN ce.itemid = 223761 AND (ce.valuenum - 32) * 5 / 9 > 38.5 THEN 1 -- Temp F converted to C
            ELSE 0
        END) +
        (CASE
            -- Hypoxemia: SpO2 < 90%
            WHEN ce.itemid IN (646, 220277) AND ce.valuenum < 90 THEN 1
            ELSE 0
        END) +
        (CASE
            -- Tachypnea: RR > 20
            WHEN ce.itemid IN (618, 220210, 224690) AND ce.valuenum > 20 THEN 1
            ELSE 0
        END) AS unstable_event_count
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    -- Join with base_stays to only process events for our cohort of interest
    INNER JOIN base_stays AS b
        ON ce.stay_id = b.stay_id
    WHERE
        -- Filter events to the first 72 hours of the ICU stay
        ce.charttime BETWEEN b.intime AND DATETIME_ADD(b.intime, INTERVAL 72 HOUR)
        -- Filter for the specific items to improve performance
        AND ce.itemid IN (
            223762, -- Temperature Celsius
            223761, -- Temperature Fahrenheit
            646,    -- SpO2
            220277, -- O2 saturation pulseoxymetry
            618,    -- Respiratory Rate
            220210, -- Respiratory Rate
            224690  -- Respiratory Rate (Total)
        )
        -- Basic data cleaning for plausible values
        AND ce.valuenum IS NOT NULL
        AND (
            (ce.itemid IN (223762, 223761) AND ce.valuenum > 0) -- Temp
            OR (ce.itemid IN (646, 220277) AND ce.valuenum > 0 AND ce.valuenum <= 100) -- SpO2
            OR (ce.itemid IN (618, 220210, 224690) AND ce.valuenum > 0 AND ce.valuenum < 100) -- RR
        )
),

-- CTE 4: Calculate the composite instability score per stay_id by summing event counts
instability_scores AS (
    SELECT
        stay_id,
        SUM(unstable_event_count) AS composite_instability_score
    FROM instability_events
    GROUP BY stay_id
),

-- CTE 5: Combine all metrics (cohort, score, LOS, mortality) for the final analysis
final_data AS (
    SELECT
        b.stay_id,
        b.cohort,
        COALESCE(s.composite_instability_score, 0) AS composite_instability_score,
        b.los AS icu_los_days,
        adm.hospital_expire_flag
    FROM base_stays AS b
    LEFT JOIN instability_scores AS s
        ON b.stay_id = s.stay_id
    -- Join to admissions to get hospital mortality flag
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON b.hadm_id = adm.hadm_id
)

-- Final step: Aggregate the metrics by cohort and calculate statistics
SELECT
    cohort,
    COUNT(stay_id) AS number_of_stays,
    -- Median and percentiles for Composite Instability Score
    APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(25)] AS instability_score_p25,
    APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(50)] AS instability_score_median,
    APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(75)] AS instability_score_p75,
    -- Median and percentiles for ICU Length of Stay (days)
    ROUND(APPROX_QUANTILES(icu_los_days, 100)[OFFSET(25)], 2) AS icu_los_days_p25,
    ROUND(APPROX_QUANTILES(icu_los_days, 100)[OFFSET(50)], 2) AS icu_los_days_median,
    ROUND(APPROX_QUANTILES(icu_los_days, 100)[OFFSET(75)], 2) AS icu_los_days_p75,
    -- Hospital mortality rate
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS hospital_mortality_percent
FROM final_data
GROUP BY cohort
ORDER BY cohort;