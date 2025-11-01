WITH ami_admissions AS (
    SELECT DISTINCT adm.subject_id, adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
    WHERE diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%'
),
troponin_t AS (
    SELECT d.itemid, d.label
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    WHERE LOWER(d.label) LIKE '%troponin t%' AND d.fluid = 'Blood'
),
first_troponin AS (
    SELECT 
        subject_id, 
        hadm_id, 
        charttime,
        valuenum AS first_troponin_value
    FROM (
        SELECT 
            le.subject_id, 
            le.hadm_id, 
            le.charttime,
            le.valuenum,
            ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime) AS rn
        FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
        INNER JOIN troponin_t tt ON le.itemid = tt.itemid
        WHERE le.valuenum > 0.01
    ) 
    WHERE rn = 1
)
SELECT
    COUNT(DISTINCT adm.subject_id) AS patient_count,
    COUNT(DISTINCT adm.hadm_id) AS admission_count,
    ROUND(AVG(p.anchor_age), 2) AS mean_age,
    ROUND(AVG(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)), 2) AS mean_los_days,
    ROUND(AVG(ft.first_troponin_value), 3) AS mean_first_troponin,
    MIN(ft.first_troponin_value) AS min_first_troponin,
    MAX(ft.first_troponin_value) AS max_first_troponin,
    SUM(adm.hospital_expire_flag) AS in_hospital_deaths,
    ROUND(SAFE_DIVIDE(SUM(adm.hospital_expire_flag), COUNT(DISTINCT adm.hadm_id)) * 100, 2) AS mortality_percent
FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
INNER JOIN ami_admissions aa
    ON adm.subject_id = aa.subject_id AND adm.hadm_id = aa.hadm_id
INNER JOIN first_troponin ft
    ON adm.subject_id = ft.subject_id AND adm.hadm_id = ft.hadm_id
WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62;