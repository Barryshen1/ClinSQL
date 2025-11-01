WITH cohort AS (
    -- First ICU stay for males aged 68-78
    SELECT 
        ie.subject_id, 
        ie.hadm_id, 
        ie.stay_id,
        ie.intime,
        ie.outtime,
        ie.los,
        p.anchor_age,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON ie.hadm_id = a.hadm_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 68 AND 78
        -- First ICU stay per patient
        AND ie.intime = (
            SELECT MIN(ie2.intime)
            FROM `physionet-data.mimiciv_3_1_icu.icustays` ie2
            WHERE ie2.subject_id = ie.subject_id
        )
),
multi_trauma AS (
    -- Patients with at least 2 distinct trauma ICD-10 codes
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE 
        -- Trauma ICD-10 codes: S00-S99, T00-T14, T20-T32
        (di.icd_code LIKE 'S%' OR di.icd_code LIKE 'T0[0-4]%' OR di.icd_code LIKE 'T1[0-4]%' OR di.icd_code LIKE 'T2%' OR di.icd_code LIKE 'T3%')
        AND di.icd_version = 10
    GROUP BY hadm_id
    HAVING COUNT(DISTINCT di.icd_code) >= 2
),
vitals_first_24h AS (
    -- Extract HR, SBP, RR in first 24h of ICU stay
    SELECT 
        c.subject_id,
        c.stay_id,
        ce.charttime,
        CASE WHEN ce.itemid = 220045 THEN ce.valuenum END AS heart_rate,
        CASE WHEN ce.itemid = 220179 THEN ce.valuenum END AS systolic_bp,
        CASE WHEN ce.itemid = 220210 THEN ce.valuenum END AS resp_rate
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.stay_id = ce.stay_id
    WHERE ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
        AND ce.itemid IN (220045, 220179, 220210)
        AND ce.valuenum IS NOT NULL
),
abnormalities AS (
    -- Flag abnormalities per measurement
    SELECT 
        subject_id,
        stay_id,
        charttime,
        CASE WHEN heart_rate > 100 THEN 1 ELSE 0 END AS tachycardia,
        CASE WHEN systolic_bp < 90 THEN 1 ELSE 0 END AS hypotension,
        CASE WHEN resp_rate > 20 THEN 1 ELSE 0 END AS tachypnea
    FROM vitals_first_24h
),
instability_scores AS (
    -- Compute instability score per patient (sum of abnormalities) and count episodes
    SELECT 
        subject_id,
        stay_id,
        SUM(tachycardia) + SUM(hypotension) + SUM(tachypnea) AS instability_score,
        SUM(tachycardia) AS tachycardia_episodes,
        SUM(hypotension) AS hypotension_episodes,
        SUM(tachypnea) AS tachypnea_episodes
    FROM abnormalities
    GROUP BY subject_id, stay_id
),
cohort_with_scores AS (
    -- Combine cohort with instability scores
    SELECT 
        c.subject_id,
        c.hadm_id,
        c.stay_id,
        c.los,
        c.hospital_expire_flag,
        COALESCE(iss.instability_score, 0) AS instability_score,
        COALESCE(iss.tachycardia_episodes, 0) AS tachycardia_episodes,
        COALESCE(iss.hypotension_episodes, 0) AS hypotension_episodes,
        COALESCE(iss.tachypnea_episodes, 0) AS tachypnea_episodes
    FROM cohort c
    INNER JOIN multi_trauma mt
        ON c.hadm_id = mt.hadm_id
    LEFT JOIN instability_scores iss
        ON c.stay_id = iss.stay_id
    WHERE iss.instability_score IS NOT NULL  -- Exclude patients with no vitals?
),
quartiles AS (
    -- Assign quartiles and deciles
    SELECT 
        *,
        NTILE(4) OVER (ORDER BY instability_score) AS quartile,
        NTILE(10) OVER (ORDER BY instability_score) AS decile
    FROM cohort_with_scores
)
-- Aggregate by quartile
SELECT 
    quartile,
    COUNT(*) AS count_patients,
    AVG(instability_score) AS mean_instability_score,
    AVG(los) AS mean_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate,
    NULL AS mean_tachycardia_episodes,  -- Placeholder for non-top decile
    NULL AS mean_hypotension_episodes,
    NULL AS mean_tachypnea_episodes
FROM quartiles
WHERE decile != 10  -- Exclude top decile for this part
GROUP BY quartile

UNION ALL

-- For top decile (10th decile)
SELECT 
    10 AS quartile,  -- Representing top decile
    COUNT(*) AS count_patients,
    AVG(instability_score) AS mean_instability_score,
    AVG(los) AS mean_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(tachycardia_episodes) AS mean_tachycardia_episodes,
    AVG(hypotension_episodes) AS mean_hypotension_episodes,
    AVG(tachypnea_episodes) AS mean_tachypnea_episodes
FROM quartiles
WHERE decile = 10
GROUP BY quartile

ORDER BY quartile;