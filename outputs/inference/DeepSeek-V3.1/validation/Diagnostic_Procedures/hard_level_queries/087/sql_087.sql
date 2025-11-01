WITH cohort AS (
    -- All ICU stays for females aged 56-66 with admission info
    SELECT 
        ie.subject_id, 
        ie.hadm_id, 
        ie.stay_id,
        ie.intime,
        ie.outtime,
        ie.los,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON ie.hadm_id = adm.hadm_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 56 AND 66
),
ich_cohort AS (
    -- Filter to those with ICH diagnosis
    SELECT 
        c.*
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON c.hadm_id = diag.hadm_id
    WHERE diag.icd_code LIKE 'I6[0-2]%'
        AND diag.icd_version = 10
),
lab_counts AS (
    -- Count distinct lab tests per ICH ICU stay in first 72h
    SELECT 
        ic.stay_id,
        COUNT(DISTINCT le.itemid) AS num_labs
    FROM ich_cohort ic
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ic.hadm_id = le.hadm_id
        AND le.charttime >= ic.intime
        AND le.charttime < DATETIME_ADD(ic.intime, INTERVAL 72 HOUR)
    GROUP BY ic.stay_id
)
SELECT
    (SELECT approx_quantiles(num_labs, 100)[OFFSET(95)] FROM lab_counts) AS percentile_95_lab_count,
    (SELECT approx_quantiles(los, 100)[OFFSET(50)] FROM ich_cohort) AS median_los_ich,
    (SELECT approx_quantiles(los, 100)[OFFSET(50)] FROM cohort) AS median_los_all,
    (SELECT AVG(hospital_expire_flag)*100 FROM ich_cohort) AS mortality_ich,
    (SELECT AVG(hospital_expire_flag)*100 FROM cohort) AS mortality_all;