WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime, 
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE pat.gender = 'M'
        AND pat.anchor_age BETWEEN 63 AND 73
        AND adm.hadm_id IN (
            SELECT hadm_id 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
            WHERE 
                (icd_version = 10 AND icd_code LIKE 'K85%') 
                OR (icd_version = 9 AND icd_code = '577.0')
        )
),

-- Step 2: Get lab events for the selected labs within 72 hours of admission
labs_72h AS (
    SELECT 
        lab.subject_id,
        lab.hadm_id,
        lab.itemid,
        lab.valuenum,
        lab.charttime
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
    INNER JOIN cohort 
        ON lab.hadm_id = cohort.hadm_id 
        AND lab.subject_id = cohort.subject_id
    WHERE lab.charttime BETWEEN cohort.admittime AND DATETIME_ADD(cohort.admittime, INTERVAL 72 HOUR)
        AND lab.itemid IN (51221, 51279, 50912, 51006, 50893)  -- HCT, CREAT, BUN, Calcium
        AND lab.valuenum IS NOT NULL
),

-- Step 3: For each patient and each lab, check if any value is critical
critical_flags AS (
    SELECT 
        hadm_id,
        subject_id,
        MAX(CASE WHEN itemid IN (51221, 51279) AND valuenum < 30 THEN 1 ELSE 0 END) AS hct_critical,
        MAX(CASE WHEN itemid = 50912 AND valuenum > 1.5 THEN 1 ELSE 0 END) AS creat_critical,
        MAX(CASE WHEN itemid = 51006 AND valuenum > 20 THEN 1 ELSE 0 END) AS bun_critical,
        MAX(CASE WHEN itemid = 50893 AND valuenum < 8.5 THEN 1 ELSE 0 END) AS calcium_critical
    FROM labs_72h
    GROUP BY hadm_id, subject_id
),

-- Step 4: Compute the instability score (sum of critical flags)
instability_scores AS (
    SELECT 
        cf.hadm_id,
        cf.subject_id,
        (cf.hct_critical + cf.creat_critical + cf.bun_critical + cf.calcium_critical) AS score
    FROM critical_flags cf
),

-- Step 5: Calculate the 90th percentile score
percentile_90 AS (
    SELECT 
        APPROX_QUANTILES(score, 100) [OFFSET(90)] AS p90_score
    FROM instability_scores
),

-- Step 6: Identify high-score patients (>=90th percentile)
high_score_patients AS (
    SELECT 
        isc.hadm_id,
        isc.subject_id,
        isc.score
    FROM instability_scores isc
    CROSS JOIN percentile_90 p90
    WHERE isc.score >= p90.p90_score
)

-- Step 7: For high-score patients, report mortality, mean LOS, and per-lab critical rates
SELECT 
    'High-score group' AS group_name,
    COUNT(*) AS n_patients,
    AVG(cohort.los_days) AS mean_los,
    SUM(cohort.hospital_expire_flag) AS mortality_count,
    AVG(cohort.hospital_expire_flag) AS mortality_rate,
    AVG(cf.hct_critical) AS hct_critical_rate,
    AVG(cf.creat_critical) AS creat_critical_rate,
    AVG(cf.bun_critical) AS bun_critical_rate,
    AVG(cf.calcium_critical) AS calcium_critical_rate
FROM high_score_patients hsp
INNER JOIN cohort 
    ON hsp.hadm_id = cohort.hadm_id AND hsp.subject_id = cohort.subject_id
INNER JOIN critical_flags cf 
    ON hsp.hadm_id = cf.hadm_id AND hsp.subject_id = cf.subject_id

UNION ALL

-- For comparison: the entire cohort
SELECT 
    'Entire cohort' AS group_name,
    COUNT(*) AS n_patients,
    AVG(cohort.los_days) AS mean_los,
    SUM(cohort.hospital_expire_flag) AS mortality_count,
    AVG(cohort.hospital_expire_flag) AS mortality_rate,
    AVG(cf.hct_critical) AS hct_critical_rate,
    AVG(cf.creat_critical) AS creat_critical_rate,
    AVG(cf.bun_critical) AS bun_critical_rate,
    AVG(cf.calcium_critical) AS calcium_critical_rate
FROM cohort
LEFT JOIN critical_flags cf 
    ON cohort.hadm_id = cf.hadm_id AND cohort.subject_id = cf.subject_id;