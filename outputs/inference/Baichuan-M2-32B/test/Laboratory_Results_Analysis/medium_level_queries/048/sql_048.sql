WITH 
hs_tnt_item AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE label LIKE '%troponin T%' 
        AND (label LIKE '%high sensitivity%' OR label LIKE '%hs%')
    LIMIT 1
),
ami_diagnoses AS (
    SELECT 
        subject_id,
        hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 10
        AND icd_code LIKE 'I21%'
        AND seq_num = 1
),
eligible_admissions AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 55 AND 65
),
ami_admissions AS (
    SELECT 
        e.hadm_id,
        e.subject_id,
        e.admittime,
        e.dischtime,
        e.age_at_admission
    FROM eligible_admissions e
    INNER JOIN ami_diagnoses d 
        ON e.hadm_id = d.hadm_id AND e.subject_id = d.subject_id
),
hs_tnt_labs AS (
    SELECT 
        l.hadm_id,
        l.subject_id,
        l.valuenum,
        l.charttime
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    INNER JOIN hs_tnt_item h ON l.itemid = h.itemid
    INNER JOIN ami_admissions a 
        ON l.hadm_id = a.hadm_id AND l.subject_id = a.subject_id
    WHERE l.charttime BETWEEN a.admittime AND a.dischtime
        AND l.valuenum > 0.01
        AND l.valueuom = 'ng/mL'
),
first_hs_tnt_per_adm AS (
    SELECT 
        hadm_id,
        subject_id,
        valuenum AS hs_tnt_value
    FROM (
        SELECT 
            hadm_id,
            subject_id,
            valuenum,
            ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
        FROM hs_tnt_labs
    ) 
    WHERE rn = 1
)
SELECT 
    COUNT(DISTINCT subject_id) AS patient_count,
    COUNT(DISTINCT hadm_id) AS admission_count,
    AVG(hs_tnt_value) AS mean_hs_tnt,
    APPROX_QUANTILES(hs_tnt_value, 100)[OFFSET(50)] AS median_hs_tnt,
    APPROX_QUANTILES(hs_tnt_value, 100)[OFFSET(25)] AS iqr_lower,
    APPROX_QUANTILES(hs_tnt_value, 100)[OFFSET(75)] AS iqr_upper
FROM first_hs_tnt_per_adm;