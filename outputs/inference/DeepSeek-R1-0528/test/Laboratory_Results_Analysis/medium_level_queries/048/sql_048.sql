WITH base_admissions_with_age AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    WHERE p.gender = 'F'
),
filtered_admissions AS (
    SELECT subject_id, hadm_id
    FROM base_admissions_with_age
    WHERE age_at_admission BETWEEN 55 AND 65
),
ami_admissions AS (
    SELECT DISTINCT diag.subject_id, diag.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    INNER JOIN filtered_admissions fa
        ON diag.subject_id = fa.subject_id AND diag.hadm_id = fa.hadm_id
    WHERE 
        (diag.icd_version = 9 AND diag.icd_code LIKE '410%') 
        OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%'))
),
troponin_tests AS (
    SELECT 
        subject_id, 
        hadm_id, 
        charttime,
        valuenum
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE itemid = 51003  -- hs-TnT
),
first_troponin_per_admission AS (
    SELECT 
        tt.subject_id,
        tt.hadm_id,
        tt.valuenum,
        ROW_NUMBER() OVER (PARTITION BY tt.hadm_id ORDER BY tt.charttime) AS rn
    FROM troponin_tests tt
    INNER JOIN ami_admissions ami 
        ON tt.subject_id = ami.subject_id AND tt.hadm_id = ami.hadm_id
),
eligible_admissions AS (
    SELECT 
        subject_id,
        hadm_id,
        valuenum AS first_troponin_t
    FROM first_troponin_per_admission
    WHERE rn = 1 
      AND valuenum > 0.01
),
main_stats AS (
    SELECT 
        COUNT(DISTINCT subject_id) AS patient_count,
        COUNT(DISTINCT hadm_id) AS admission_count,
        AVG(first_troponin_t) AS mean_troponin_t
    FROM eligible_admissions
),
quantiles AS (
    SELECT 
        APPROX_QUANTILES(first_troponin_t, 100) AS q_arr
    FROM eligible_admissions
)
SELECT 
    patient_count,
    admission_count,
    mean_troponin_t,
    q_arr[OFFSET(25)] AS q1_troponin_t,
    q_arr[OFFSET(50)] AS median_troponin_t,
    q_arr[OFFSET(75)] AS q3_troponin_t,
    q_arr[OFFSET(75)] - q_arr[OFFSET(25)] AS iqr_troponin_t
FROM main_stats, quantiles;