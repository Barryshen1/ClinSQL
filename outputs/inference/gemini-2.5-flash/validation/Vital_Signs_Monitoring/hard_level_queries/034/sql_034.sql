WITH cohort_filtered AS (
    -- Step 1: Identify the cohort of female patients aged 60-70 with mixed shock
    SELECT DISTINCT
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        p.gender,
        CAST(p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS BIGNUMERIC) AS age_at_icu_admission,
        ie.intime,
        ie.outtime,
        ie.los AS icu_los,
        adm.hospital_expire_flag AS mortality_flag
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON ie.hadm_id = adm.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ie.hadm_id = di.hadm_id
    WHERE
        p.gender = 'F'
        AND CAST(p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS BIGNUMERIC) BETWEEN 60 AND 70
        AND (
            -- ICD-10 codes for various types of shock and severe sepsis/septic shock
            (di.icd_version = 10 AND (
                di.icd_code LIKE 'R57%' OR           -- Shock, not elsewhere classified (e.g., Cardiogenic, Hypovolemic, Other)
                di.icd_code LIKE 'R65.2%' OR         -- Severe sepsis and septic shock
                di.icd_code LIKE 'T78.2%' OR         -- Anaphylactic shock
                di.icd_code LIKE 'T79.4%'            -- Traumatic shock
            ))
            OR
            -- ICD-9 codes for various types of shock and severe sepsis/septic shock
            (di.icd_version = 9 AND (
                di.icd_code LIKE '785.5%' OR         -- Shock (e.g., Cardiogenic, Hypovolemic, Septic, Other)
                di.icd_code IN ('99591', '99592') OR -- Sepsis, Severe Sepsis (ICD-9 specific for 995.91, 995.92)
                di.icd_code LIKE '999.0%' OR         -- Anaphylactic shock due to serum
                di.icd_code LIKE '958.4%'            -- Traumatic shock
            ))
        )
),
vitals_raw AS (
    -- Step 2: Extract relevant vital signs within the first 48 hours of ICU stay for the cohort
    SELECT
        cf.subject_id,
        cf.hadm_id,
        cf.stay_id,
        ce.charttime,
        cf.intime,
        cf.icu_los,
        cf.mortality_flag,
        -- Prioritize invasive MAP (220052) over non-invasive (220181) if both exist at a charttime
        COALESCE(
            MAX(CASE WHEN ce.itemid = 220052 THEN ce.valuenum ELSE NULL END),
            MAX(CASE WHEN ce.itemid = 220181 THEN ce.valuenum ELSE NULL END)
        ) AS map,
        MAX(CASE WHEN ce.itemid = 220045 THEN ce.valuenum ELSE NULL END) AS hr, -- Heart Rate
        MAX(CASE WHEN ce.itemid = 220210 THEN ce.valuenum ELSE NULL END) AS rr, -- Respiratory Rate
        -- Prioritize Celsius (223762), convert Fahrenheit (223761) to Celsius if only F is present
        COALESCE(
            MAX(CASE WHEN ce.itemid = 223762 THEN ce.valuenum ELSE NULL END),
            MAX(CASE WHEN ce.itemid = 223761 THEN (ce.valuenum - 32) * 5/9 ELSE NULL END)
        ) AS temp_c_final,
        MAX(CASE WHEN ce.itemid = 220277 THEN ce.valuenum ELSE NULL END) AS spo2 -- SpO2
    FROM
        cohort_filtered cf
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON cf.subject_id = ce.subject_id
        AND cf.hadm_id = ce.hadm_id
        AND cf.stay_id = ce.stay_id
    WHERE
        ce.charttime BETWEEN cf.intime AND DATETIME_ADD(cf.intime, INTERVAL 48 HOUR)
        AND ce.itemid IN (220045, 220052, 220181, 220210, 223761, 223762, 220277)
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0 -- Exclude zero or negative values for vitals
    GROUP BY
        cf.subject_id, cf.hadm_id, cf.stay_id, ce.charttime, cf.intime, cf.icu_los, cf.mortality_flag
),
instability_scores_per_charttime AS (
    -- Step 3: Calculate abnormality flags for each vital sign at each charttime
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        intime,
        icu_los,
        mortality_flag,
        (CASE WHEN hr IS NOT NULL AND (hr < 50 OR hr > 100) THEN 1 ELSE 0 END) AS hr_abnormal_flag,
        (CASE WHEN map IS NOT NULL AND (map < 65 OR map > 100) THEN 1 ELSE 0 END) AS map_abnormal_flag,
        (CASE WHEN rr IS NOT NULL AND (rr < 10 OR rr > 25) THEN 1 ELSE 0 END) AS rr_abnormal_flag,
        (CASE WHEN temp_c_final IS NOT NULL AND (temp_c_final < 36 OR temp_c_final > 38) THEN 1 ELSE 0 END) AS temp_abnormal_flag,
        (CASE WHEN spo2 IS NOT NULL AND spo2 < 90 THEN 1 ELSE 0 END) AS spo2_abnormal_flag,
        -- Binary flags for specific outcomes (calculated here per charttime, then aggregated to 'any' later)
        (CASE WHEN map IS NOT NULL AND map < 65 THEN 1 ELSE 0 END) AS is_hypotensive_at_time,
        (CASE WHEN hr IS NOT NULL AND hr > 100 THEN 1 ELSE 0 END) AS is_tachycardic_at_time
    FROM
        vitals_raw
),
instability_summary_per_stay AS (
    -- Step 4: Aggregate instability score and outcome flags per ICU stay
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        -- If no vital signs are present within 48h, instability score and flags will be 0.
        COALESCE(MAX(
            hr_abnormal_flag +
            map_abnormal_flag +
            rr_abnormal_flag +
            temp_abnormal_flag +
            spo2_abnormal_flag
        ), 0) AS instability_score_max_simultaneous, -- Max number of simultaneous abnormalities
        MAX(is_hypotensive_at_time) AS has_hypotension, -- 1 if *any* MAP < 65 within 48h
        MAX(is_tachycardic_at_time) AS has_tachycardia, -- 1 if *any* HR > 100 within 48h
        MAX(icu_los) AS icu_los, -- Max is fine as it's constant per stay
        MAX(mortality_flag) AS mortality_flag -- Max is fine as it's constant per stay
    FROM
        instability_scores_per_charttime
    GROUP BY
        subject_id, hadm_id, stay_id
),
instability_with_percentiles AS (
    -- Step 5: Calculate deciles and percentile ranks for instability scores
    SELECT
        *,
        NTILE(10) OVER (ORDER BY instability_score_max_simultaneous DESC) AS instability_decile,
        PERCENT_RANK() OVER (ORDER BY instability_score_max_simultaneous) AS instability_percent_rank
    FROM
        instability_summary_per_stay
)
-- Step 6: Final comparison for the entire cohort and the top decile
SELECT
    -- Cohort metrics
    APPROX_QUANTILES(instability_score_max_simultaneous, 100)[OFFSET(94)] AS cohort_95th_percentile_instability_score,
    AVG(icu_los) AS cohort_avg_icu_los_days,
    SUM(mortality_flag) * 100.0 / COUNT(*) AS cohort_mortality_rate_percent,
    SUM(has_hypotension) * 100.0 / COUNT(*) AS cohort_hypotension_rate_percent,
    SUM(has_tachycardia) * 100.0 / COUNT(*) AS cohort_tachycardia_rate_percent,

    -- Top Decile (instability_decile = 1, representing highest instability) metrics
    AVG(CASE WHEN instability_decile = 1 THEN icu_los ELSE NULL END) AS top_decile_avg_icu_los_days,
    SUM(CASE WHEN instability_decile = 1 THEN mortality_flag ELSE 0 END) * 100.0 / SUM(CASE WHEN instability_decile = 1 THEN 1 ELSE 0 END) AS top_decile_mortality_rate_percent,
    SUM(CASE WHEN instability_decile = 1 THEN has_hypotension ELSE 0 END) * 100.0 / SUM(CASE WHEN instability_decile = 1 THEN 1 ELSE 0 END) AS top_decile_hypotension_rate_percent,
    SUM(CASE WHEN instability_decile = 1 THEN has_tachycardia ELSE 0 END) * 100.0 / SUM(CASE WHEN instability_decile = 1 THEN 1 ELSE 0 END) AS top_decile_tachycardia_rate_percent
FROM
    instability_with_percentiles;