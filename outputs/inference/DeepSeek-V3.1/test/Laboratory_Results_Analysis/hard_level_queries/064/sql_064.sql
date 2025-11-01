WITH base_cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime, 
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR)/24.0 AS los_days,
        pat.anchor_age,
        -- Flag for acute pancreatitis: ICD-9 '5770' or ICD-10 starting with 'K85'
        MAX(CASE WHEN (diag.icd_version = 9 AND diag.icd_code = '5770') 
                  OR (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%') 
                 THEN 1 ELSE 0 END) AS has_pancreatitis
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE pat.gender = 'F'
        AND pat.anchor_age BETWEEN 65 AND 75
    GROUP BY adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag, pat.anchor_age
),

-- Get labs in first 48 hours
labs AS (
    SELECT 
        lab.subject_id,
        lab.hadm_id,
        lab.itemid,
        lab.valuenum,
        lab.charttime,
        lab.ref_range_lower,
        lab.ref_range_upper
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
    INNER JOIN base_cohort coh
        ON lab.hadm_id = coh.hadm_id
    WHERE lab.charttime BETWEEN coh.admittime AND DATETIME_ADD(coh.admittime, INTERVAL 48 HOUR)
        AND lab.valuenum IS NOT NULL
        AND lab.ref_range_lower IS NOT NULL
        AND lab.ref_range_upper IS NOT NULL
),

-- For each patient, check if any value is critical
critical_labs AS (
    SELECT 
        hadm_id,
        MAX(CASE WHEN valuenum < ref_range_lower OR valuenum > ref_range_upper THEN 1 ELSE 0 END) AS is_critical
    FROM labs
    GROUP BY hadm_id
),

-- Compute instability score per patient (number of distinct lab types with critical value)
instability_scores AS (
    SELECT 
        labs.hadm_id,
        COUNT(DISTINCT labs.itemid) AS instability_score
    FROM labs
    WHERE labs.valuenum < labs.ref_range_lower OR labs.valuenum > labs.ref_range_upper
    GROUP BY labs.hadm_id
),

-- Combine with base cohort
cohort_with_scores AS (
    SELECT
        coh.*,
        COALESCE(isc.instability_score, 0) AS instability_score,
        COALESCE(cl.is_critical, 0) AS has_critical_labs
    FROM base_cohort coh
    LEFT JOIN instability_scores isc
        ON coh.hadm_id = isc.hadm_id
    LEFT JOIN critical_labs cl
        ON coh.hadm_id = cl.hadm_id
),

-- For pancreatitis cases only, compute quintiles of instability score
cases_with_quintiles AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY instability_score) AS quintile
    FROM cohort_with_scores
    WHERE has_pancreatitis = 1
),

-- Aggregate by quintile for cases
quintile_summary AS (
    SELECT
        quintile,
        COUNT(*) AS count,
        AVG(instability_score) AS mean_instability,
        AVG(los_days) AS mean_los,
        AVG(hospital_expire_flag) AS mortality_rate
    FROM cases_with_quintiles
    GROUP BY quintile
),

-- Overall % with critical labs for cases (pancreatitis)
cases_critical_percent AS (
    SELECT
        AVG(has_critical_labs) * 100 AS cases_critical_pct
    FROM cohort_with_scores
    WHERE has_pancreatitis = 1
),

-- For non-pancreatitis controls: % with critical labs
controls_critical_percent AS (
    SELECT
        AVG(has_critical_labs) * 100 AS controls_critical_pct
    FROM cohort_with_scores
    WHERE has_pancreatitis = 0
)

-- Final output
SELECT
    q.quintile,
    q.count,
    q.mean_instability,
    q.mean_los,
    q.mortality_rate,
    c1.cases_critical_pct AS pancreatitis_critical_pct,
    c2.controls_critical_pct AS control_critical_pct
FROM quintile_summary q
CROSS JOIN cases_critical_percent c1
CROSS JOIN controls_critical_percent c2
ORDER BY q.quintile;