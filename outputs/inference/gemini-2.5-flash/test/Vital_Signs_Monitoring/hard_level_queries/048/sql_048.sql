WITH base_cohort AS (
    SELECT
        p.subject_id,
        adm.hadm_id,
        icu.stay_id,
        p.gender,
        p.anchor_age AS age_at_admission,
        icu.intime,
        icu.outtime,
        icu.los, -- ICU length of stay in days
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
        p.gender = 'F'
        AND p.anchor_age BETWEEN 75 AND 85
),
-- Step 2: Identify Patients on Invasive Mechanical Ventilation within first 48 hours of ICU Stay.
vent_events AS (
    SELECT DISTINCT
        ce.stay_id
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN
        base_cohort bc
        ON ce.stay_id = bc.stay_id
    WHERE
        ce.charttime BETWEEN bc.intime AND DATETIME_ADD(bc.intime, INTERVAL 48 HOUR)
        AND (
               (ce.itemid = 223848 AND LOWER(ce.value) IN ('true', 'on', 'active')) -- Mechanical Ventilator status
            OR (ce.itemid = 225792 AND LOWER(ce.value) NOT IN (
                'off', 'spontaneous', 'cpap', 'bipap (pressure support)',
                'bipap (volume support)', 'nppv', 'pressure support ventilation',
                'volume support ventilation', 'nippv')) -- Exclude non-invasive modes
            OR (ce.itemid = 224687 AND LOWER(ce.value) IN ('true', 'present', 'ett', 'endotracheal')) -- ET Tube present
        )
),
ventilated_cohort AS (
    SELECT
        bc.*
    FROM
        base_cohort bc
    INNER JOIN
        vent_events ve
        ON bc.stay_id = ve.stay_id
),
-- Step 3: Calculate 48-hour Instability Component Flags for each valid ICU stay.
vital_signs_48hr AS (
    SELECT
        vc.stay_id,
        MAX(CASE
            WHEN (ce.itemid = 220052 AND ce.valuenum < 65)  -- MAP < 65
            OR (ce.itemid = 220179 AND ce.valuenum < 90)    -- SBP < 90
            THEN 1 ELSE 0 END) AS has_hypotension_48hr,
        MAX(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS has_tachycardia_48hr, -- HR > 100
        MAX(CASE WHEN ce.itemid = 220210 AND (ce.valuenum < 10 OR ce.valuenum > 25) THEN 1 ELSE 0 END) AS has_resp_instability_48hr, -- RR < 10 or > 25
        MAX(CASE WHEN ce.itemid = 220277 AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS has_hypoxemia_48hr, -- SpO2 < 90
        MAX(CASE
            WHEN (ce.itemid = 223761 AND ((ce.valuenum - 32) * 5/9 < 36 OR (ce.valuenum - 32) * 5/9 > 38.5)) -- Temp F converted to C
            OR (ce.itemid = 223762 AND (ce.valuenum < 36 OR ce.valuenum > 38.5)) -- Temp C
            THEN 1 ELSE 0 END) AS has_temp_instability_48hr
    FROM
        ventilated_cohort vc
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON vc.stay_id = ce.stay_id
    WHERE
        ce.charttime BETWEEN vc.intime AND DATETIME_ADD(vc.intime, INTERVAL 48 HOUR)
        AND ce.valuenum IS NOT NULL -- Vital signs must have a numeric value
    GROUP BY
        vc.stay_id
),
vasopressor_48hr AS (
    SELECT DISTINCT
        vc.stay_id,
        1 AS has_vasopressor_48hr
    FROM
        ventilated_cohort vc
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.inputevents` ie
        ON vc.stay_id = ie.stay_id
    WHERE
        ie.starttime BETWEEN vc.intime AND DATETIME_ADD(vc.intime, INTERVAL 48 HOUR)
        AND ie.itemid IN (
            221906, -- Norepinephrine
            221908, -- Phenylephrine
            221653, -- Dopamine
            221289, -- Epinephrine
            222011  -- Vasopressin
        )
        AND ie.amount IS NOT NULL AND ie.amount > 0
    GROUP BY vc.stay_id
),
-- Step 4: Calculate 48-hour Composite Instability Score
instability_score AS (
    SELECT
        vc.subject_id,
        vc.hadm_id,
        vc.stay_id,
        vc.los,
        vc.hospital_expire_flag,
        COALESCE(vs.has_hypotension_48hr, 0) AS actual_hypotension_flag, -- Retain for outcome calc
        COALESCE(vs.has_tachycardia_48hr, 0) AS actual_tachycardia_flag, -- Retain for outcome calc
        (
            COALESCE(vs.has_hypotension_48hr, 0) +
            COALESCE(vs.has_tachycardia_48hr, 0) +
            COALESCE(vs.has_resp_instability_48hr, 0) +
            COALESCE(vs.has_hypoxemia_48hr, 0) +
            COALESCE(vs.has_temp_instability_48hr, 0) +
            COALESCE(vp.has_vasopressor_48hr, 0)
        ) AS composite_instability_score
    FROM
        ventilated_cohort vc
    LEFT JOIN vital_signs_48hr vs
        ON vc.stay_id = vs.stay_id
    LEFT JOIN vasopressor_48hr vp
        ON vc.stay_id = vp.stay_id
),
-- Step 5 & 6: Calculate 90th percentile of the score and assign quartile ranks.
percentiles_and_quartiles AS (
    SELECT
        *,
        PERCENTILE_CONT(composite_instability_score, 0.9) OVER() AS p90_instability_score,
        NTILE(4) OVER (ORDER BY composite_instability_score DESC) AS instability_score_quartile
    FROM
        instability_score
),
-- Step 7: Filter for the top 25% (highest score) group, and prepare final aggregations.
results AS (
    SELECT
        p90_instability_score,
        -- Outcomes for the top 25% group (instability_score_quartile = 1)
        AVG(CASE WHEN instability_score_quartile = 1 THEN actual_hypotension_flag ELSE NULL END) * 100 AS hypotension_in_top_25_percent,
        AVG(CASE WHEN instability_score_quartile = 1 THEN actual_tachycardia_flag ELSE NULL END) * 100 AS tachycardia_in_top_25_percent,
        AVG(CASE WHEN instability_score_quartile = 1 THEN los ELSE NULL END) AS icu_los_in_top_25_percent_days,
        AVG(CASE WHEN instability_score_quartile = 1 THEN hospital_expire_flag ELSE NULL END) * 100 AS mortality_in_top_25_percent
    FROM
        percentiles_and_quartiles
    GROUP BY
        p90_instability_score
)
-- Final Select
SELECT
    p90_instability_score,
    hypotension_in_top_25_percent,
    tachycardia_in_top_25_percent,
    icu_los_in_top_25_percent_days,
    mortality_in_top_25_percent
FROM
    results;