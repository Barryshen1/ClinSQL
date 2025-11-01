WITH patients_filtered AS (
    SELECT 
        p.subject_id,
        a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 84 AND 94
),

acs_diagnoses AS (
    SELECT 
        di.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE di.icd_code IN (
        'I20.0', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9',
        'I22.0', 'I22.1', 'I22.2', 'I22.8', 'I22.9'
    )
),

initial_troponin AS (
    SELECT 
        le.hadm_id,
        le.valuenum,
        le.ref_range_upper,
        ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di 
        ON le.itemid = di.itemid
    WHERE di.label LIKE '%TROPONIN%I%'
)

SELECT 
    COUNT(*) AS count,
    AVG(valuenum) AS mean,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valuenum) AS median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) - 
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum) AS iqr
FROM (
    SELECT 
        it.valuenum
    FROM initial_troponin it
    JOIN patients_filtered pf 
        ON it.hadm_id = pf.hadm_id
    JOIN acs_diagnoses ad 
        ON it.hadm_id = ad.hadm_id
    WHERE it.rn = 1
        AND it.valuenum > it.ref_range_upper
) AS filtered_patients;