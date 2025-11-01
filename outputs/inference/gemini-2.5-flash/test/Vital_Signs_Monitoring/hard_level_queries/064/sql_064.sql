WITH Cohort AS (
    -- 1. Identify male ICU patients aged 45-55 with ARF diagnosis
    SELECT
        p.subject_id,
        adm.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        icu.los,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 45 AND 55
        AND (
            (diag.icd_version = 9 AND SUBSTR(diag.icd_code, 1, 3) = '584') OR -- ICD-9 Acute Kidney Failure
            (diag.icd_version = 10 AND SUBSTR(diag.icd_code, 1, 3) = 'N17')   -- ICD-10 Acute Kidney Failure
        )
    GROUP BY -- Deduplicate in case of multiple ARF diagnoses for the same admission/stay
        p.subject_id, adm.hadm_id, icu.stay_id, icu.intime, icu.outtime, icu.los, adm.hospital_expire_flag
),
First48hEvents AS (
    -- 2. Collect relevant physiological data within the first 48 hours of each ICU stay
    SELECT
        c.subject_id,
        c.stay_id,
        c.intime,
        c.los,
        c.hospital_expire_flag,
        -- Hypotension: MAP < 65 mmHg
        MAX(CASE WHEN ce.itemid IN (220052, 220181) AND ce.valuenum IS NOT NULL AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS has_hypotension,
        -- Tachycardia: Heart Rate > 100 bpm
        MAX(CASE WHEN ce.itemid = 220045 AND ce.valuenum IS NOT NULL AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS has_tachycardia,
        -- Tachypnea: Respiratory Rate > 22 bpm
        MAX(CASE WHEN ce.itemid = 220210 AND ce.valuenum IS NOT NULL AND ce.valuenum > 22 THEN 1 ELSE 0 END) AS has_tachypnea,
        -- Temperature Derangement: Temp > 38.5 C OR < 35 C
        MAX(CASE WHEN ce.itemid = 223761 AND ce.valuenum IS NOT NULL AND (ce.valuenum >= 38.5 OR ce.valuenum <= 35.0) THEN 1 ELSE 0 END) AS has_temp_derangement,
        -- Hypoxemia: SpO2 < 90%
        MAX(CASE WHEN ce.itemid = 220277 AND ce.valuenum IS NOT NULL AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS has_hypoxemia,
        -- Altered Mental Status: GCS Total < 13
        MAX(CASE WHEN ce.itemid = 227013 AND ce.valuenum IS NOT NULL AND ce.valuenum < 13 THEN 1 ELSE 0 END) AS has_low_gcs,
        -- Elevated Lactate: Lactate > 2.0 mmol/L
        MAX(CASE WHEN le.itemid = 50813 AND le.valuenum IS NOT NULL AND le.valuenum > 2.0 THEN 1 ELSE 0 END) AS has_high_lactate
    FROM
        Cohort c
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.stay_id = ce.stay_id
        AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON c.subject_id = le.subject_id
        AND c.hadm_id = le.hadm_id -- Link labevents also by hadm_id for robustness
        AND le.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    GROUP BY
        c.subject_id, c.stay_id, c.intime, c.los, c.hospital_expire_flag
),
Scores AS (
    -- 3. Calculate Composite Instability Score and assign quartiles
    SELECT
        f48.subject_id,
        f48.stay_id,
        f48.intime,
        f48.los,
        f48.hospital_expire_flag,
        f48.has_hypotension, -- Retain for direct comparison
        f48.has_tachycardia, -- Retain for direct comparison
        (
            f48.has_hypotension +
            f48.has_tachycardia +
            f48.has_tachypnea +
            f48.has_temp_derangement +
            f48.has_hypoxemia +
            f48.has_low_gcs +
            f48.has_high_lactate
        ) AS composite_instability_score,
        -- Rank patients into quartiles based on their instability score (highest score = Q1)
        NTILE(4) OVER (ORDER BY (
            f48.has_hypotension +
            f48.has_tachycardia +
            f48.has_tachypnea +
            f48.has_temp_derangement +
            f48.has_hypoxemia +
            f48.has_low_gcs +
            f48.has_high_lactate
        ) DESC) AS instability_quartile,
        -- Calculate the 95th percentile score for the overall cohort
        PERCENTILE_CONT( (
            f48.has_hypotension +
            f48.has_tachycardia +
            f48.has_tachypnea +
            f48.has_temp_derangement +
            f48.has_hypoxemia +
            f48.has_low_gcs +
            f48.has_high_lactate
        ), 0.95) OVER () AS p95_instability_score_all_cohort
    FROM
        First48hEvents f48
)
-- 4. Compare metrics between top quartile and the rest of the age-matched cohort
SELECT
    'Top Quartile (Q1)' AS cohort_group,
    COUNT(DISTINCT s.stay_id) AS num_icu_stays,
    -- The 95th percentile value from the original request
    MAX(s.p95_instability_score_all_cohort) AS p95_overall_instability_score,
    -- Comparisons for the top quartile
    AVG(CAST(s.composite_instability_score AS BIGNUMERIC)) AS avg_instability_score_Q1,
    AVG(CAST(s.has_hypotension AS BIGNUMERIC)) AS prop_hypotension_Q1,
    AVG(CAST(s.has_tachycardia AS BIGNUMERIC)) AS prop_tachycardia_Q1,
    AVG(CAST(s.los AS BIGNUMERIC)) AS avg_icu_los_Q1,
    AVG(CAST(s.hospital_expire_flag AS BIGNUMERIC)) AS prop_mortality_Q1
FROM
    Scores s
WHERE
    s.instability_quartile = 1
GROUP BY
    cohort_group

UNION ALL

SELECT
    'Rest of Cohort (Q2-Q4)' AS cohort_group,
    COUNT(DISTINCT s.stay_id) AS num_icu_stays,
    MAX(s.p95_instability_score_all_cohort) AS p95_overall_instability_score,
    -- Comparisons for the rest of the cohort
    AVG(CAST(s.composite_instability_score AS BIGNUMERIC)) AS avg_instability_score_Q2_Q4,
    AVG(CAST(s.has_hypotension AS BIGNUMERIC)) AS prop_hypotension_Q2_Q4,
    AVG(CAST(s.has_tachycardia AS BIGNUMERIC)) AS prop_tachycardia_Q2_Q4,
    AVG(CAST(s.los AS BIGNUMERIC)) AS avg_icu_los_Q2_Q4,
    AVG(CAST(s.hospital_expire_flag AS BIGNUMERIC)) AS prop_mortality_Q2_Q4
FROM
    Scores s
WHERE
    s.instability_quartile > 1
GROUP BY
    cohort_group
ORDER BY cohort_group;