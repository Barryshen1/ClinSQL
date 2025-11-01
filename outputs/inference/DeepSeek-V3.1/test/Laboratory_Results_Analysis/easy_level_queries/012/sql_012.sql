WITH stroke_patients AS (
    SELECT DISTINCT p.subject_id, p.gender, p.anchor_age, d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
        ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
    WHERE p.anchor_age = 87
        AND p.gender = 'F'
        AND diag.icd_code LIKE 'I6[0-2]%'
        AND d.icd_version = 10
),
platelet_labs AS (
    SELECT l.valuenum
    FROM stroke_patients s
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON s.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
        ON s.hadm_id = l.hadm_id AND s.subject_id = l.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
        ON l.itemid = li.itemid
    WHERE li.label = 'Platelet Count'
        AND l.valuenum IS NOT NULL
        AND DATE(l.charttime) = DATE(a.dischtime)
)
SELECT APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS percentile_75
FROM platelet_labs;