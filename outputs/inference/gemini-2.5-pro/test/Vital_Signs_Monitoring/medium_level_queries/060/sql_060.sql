WITH

-- Step 1: Identify the cohort of female ICU patients aged 70-80
icu_cohort AS (
    SELECT
        p.subject_id,
        i.hadm_id,
        i.stay_id,
        i.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON i.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 70 AND 80
),

-- Step 2: Find the maximum SBP for each stay in the first 24 hours
sbp_data AS (
    SELECT
        c.stay_id,
        c.hadm_id,
        MAX(ce.valuenum) AS max_sbp
    FROM icu_cohort AS c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        ON c.stay_id = ce.stay_id
    WHERE
        -- Filter for SBP itemids (Non-Invasive and Arterial)
        ce.itemid IN (220179, 220050, 225309)
        -- Filter for plausible SBP values
        AND ce.valuenum > 0 AND ce.valuenum < 400
        -- Filter for the first 24 hours of the ICU stay
        AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
    GROUP BY
        c.stay_id, c.hadm_id
),

-- Step 3: Identify hospital admissions with a stroke diagnosis
stroke_diagnoses AS (
    SELECT DISTINCT
        hadm_id,
        1 AS has_stroke
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 codes for stroke
        (icd_version = 9 AND (
            icd_code LIKE '430%' -- Subarachnoid hemorrhage
            OR icd_code LIKE '431%' -- Intracerebral hemorrhage
            OR icd_code LIKE '432%' -- Other and unspecified intracranial hemorrhage
            OR icd_code LIKE '433%' -- Occlusion and stenosis of precerebral arteries
            OR icd_code LIKE '434%' -- Occlusion of cerebral arteries
            OR icd_code LIKE '436%' -- Acute, but ill-defined, cerebrovascular disease
        ))
        -- ICD-10 codes for stroke
        OR (icd_version = 10 AND (
            icd_code LIKE 'I60%'  -- Subarachnoid hemorrhage
            OR icd_code LIKE 'I61%'  -- Intracerebral hemorrhage
            OR icd_code LIKE 'I62%'  -- Other nontraumatic intracranial hemorrhage
            OR icd_code LIKE 'I63%'  -- Cerebral infarction
            OR icd_code LIKE 'I64%'  -- Stroke, not specified as haemorrhage or infarction
        ))
),

-- Step 4: Combine SBP data with stroke flags and categorize SBP
categorized_stays AS (
    SELECT
        sd.stay_id,
        sd.max_sbp,
        COALESCE(dx.has_stroke, 0) AS has_stroke,
        CASE
            WHEN sd.max_sbp < 130 THEN '<130'
            WHEN sd.max_sbp >= 130 AND sd.max_sbp < 140 THEN '130-139'
            WHEN sd.max_sbp >= 140 AND sd.max_sbp < 160 THEN '140-159'
            WHEN sd.max_sbp >= 160 THEN '>=160'
        END AS sbp_category
    FROM sbp_data AS sd
    LEFT JOIN stroke_diagnoses AS dx
        ON sd.hadm_id = dx.hadm_id
)

-- Step 5: Aggregate results by SBP category and calculate final metrics
SELECT
    sbp_category,
    COUNT(stay_id) AS number_of_patients,
    ROUND(COUNT(stay_id) * 100.0 / SUM(COUNT(stay_id)) OVER (), 2) AS percent_of_total_patients,
    ROUND(AVG(has_stroke) * 100.0, 2) AS stroke_rate_percent
FROM categorized_stays
GROUP BY
    sbp_category
ORDER BY
    CASE
        WHEN sbp_category = '<130' THEN 1
        WHEN sbp_category = '130-139' THEN 2
        WHEN sbp_category = '140-159' THEN 3
        WHEN sbp_category = '>=160' THEN 4
    END;