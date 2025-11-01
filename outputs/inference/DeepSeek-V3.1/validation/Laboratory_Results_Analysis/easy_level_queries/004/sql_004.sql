WITH sepsis_patients AS (
    SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON a.subject_id = diag.subject_id AND a.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE p.anchor_age = 76
        AND p.gender = 'F'
        AND (
            (diag.icd_version = 10 AND (d.icd_code LIKE 'A41%' OR d.icd_code = 'R65.2'))
            OR (diag.icd_version = 9 AND d.icd_code LIKE '038%')
        )
),
platelet_avg_per_patient AS (
    SELECT sp.subject_id, sp.hadm_id, AVG(le.valuenum) AS avg_platelet
    FROM sepsis_patients sp
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON sp.subject_id = le.subject_id AND sp.hadm_id = le.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE le.itemid = 51265  -- platelet count
        AND le.valuenum IS NOT NULL
        AND le.charttime >= sp.admittime
        AND le.charttime <= DATETIME_ADD(sp.admittime, INTERVAL 24 HOUR)
    GROUP BY sp.subject_id, sp.hadm_id
)
SELECT APPROX_QUANTILES(avg_platelet, 2)[OFFSET(1)] AS median_platelet
FROM platelet_avg_per_patient;