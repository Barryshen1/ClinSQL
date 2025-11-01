WITH
-- Step 1: Define the cohort of male patients, 55-65 years old, with a cardiac arrest diagnosis
cohort AS (
    SELECT
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.los,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
            ON icu.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
            ON icu.hadm_id = adm.hadm_id
    WHERE
        pat.gender = 'M'
        -- Calculate age at ICU admission and filter
        AND (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year + pat.anchor_age) BETWEEN 55 AND 65
        -- Filter for patients with a diagnosis of cardiac arrest
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
            WHERE dx.hadm_id = icu.hadm_id
            AND (
                   (dx.icd_code = '4275' AND dx.icd_version = 9) -- Cardiac arrest, ICD-9
                OR (dx.icd_code LIKE 'I46%' AND dx.icd_version = 10) -- Cardiac arrest, ICD-10
            )
        )
),

-- Step 2: Extract relevant vital signs from the first 24 hours of the ICU stay for the cohort
first_24h_vitals AS (
    SELECT
        c.stay_id,
        CASE
            WHEN ce.itemid = 220045 THEN 'HR'
            WHEN ce.itemid IN (220052, 220181) THEN 'MAP'
            WHEN ce.itemid = 220210 THEN 'RR'
            WHEN ce.itemid = 220277 THEN 'SPO2'
        END AS vital_sign,
        ce.valuenum
    FROM
        cohort AS c
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
            ON c.stay_id = ce.stay_id
    WHERE
        ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
        AND ce.itemid IN (
            220045, -- Heart Rate
            220052, -- Arterial Blood Pressure mean
            220181, -- Non Invasive Blood Pressure mean
            220210, -- Respiratory Rate
            220277  -- O2 saturation pulseoxymetry
        )
        -- Basic data cleaning to remove obvious errors
        AND ce.valuenum IS NOT NULL
        AND CASE
            WHEN ce.itemid = 220045 THEN ce.valuenum > 0 AND ce.valuenum < 300
            WHEN ce.itemid IN (220052, 220181) THEN ce.valuenum > 0 AND ce.valuenum < 300
            WHEN ce.itemid = 220210 THEN ce.valuenum > 0 AND ce.valuenum < 100
            WHEN ce.itemid = 220277 THEN ce.valuenum > 0 AND ce.valuenum <= 100
            ELSE TRUE
        END
),

-- Step 3: For each stay, calculate the coefficient of variation (CV) for each vital sign
vital_cv AS (
    SELECT
        stay_id,
        vital_sign,
        SAFE_DIVIDE(STDDEV_SAMP(valuenum), AVG(valuenum)) AS cv
    FROM
        first_24h_vitals
    GROUP BY
        stay_id, vital_sign
    HAVING COUNT(valuenum) > 1 -- Standard deviation requires at least 2 points
),

-- Step 4: Pivot the CVs and calculate a final composite instability score for each stay
instability_scores AS (
    SELECT
        stay_id,
        (
            COALESCE(MAX(IF(vital_sign = 'HR', cv, NULL)), 0) +
            COALESCE(MAX(IF(vital_sign = 'MAP', cv, NULL)), 0) +
            COALESCE(MAX(IF(vital_sign = 'RR', cv, NULL)), 0) +
            COALESCE(MAX(IF(vital_sign = 'SPO2', cv, NULL)), 0)
        ) * 100 AS instability_score
    FROM
        vital_cv
    GROUP BY
        stay_id
),

-- Step 5: Join scores back to cohort outcomes and assign instability deciles
final_data AS (
    SELECT
        c.stay_id,
        c.los,
        c.hospital_expire_flag,
        isc.instability_score,
        NTILE(10) OVER(ORDER BY isc.instability_score DESC) AS instability_decile
    FROM
        cohort AS c
    INNER JOIN
        instability_scores AS isc ON c.stay_id = isc.stay_id
),

-- Step 6: Perform the two requested calculations in parallel
percentile_calc AS (
    SELECT
        (COUNTIF(instability_score <= 70) * 100.0) / COUNT(stay_id) AS percentile_of_score_70
    FROM
        final_data
),
top_decile_stats AS (
    SELECT
        AVG(los) AS mean_icu_los_top_decile,
        AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_rate_percent_top_decile
    FROM
        final_data
    WHERE
        instability_decile = 1
)

-- Final Step: Combine the results into a single output row
SELECT
    p.percentile_of_score_70,
    t.mean_icu_los_top_decile,
    t.mortality_rate_percent_top_decile
FROM
    percentile_calc AS p,
    top_decile_stats AS t;