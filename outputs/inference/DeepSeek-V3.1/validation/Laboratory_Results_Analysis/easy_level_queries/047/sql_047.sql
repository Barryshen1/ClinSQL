WITH hf_admissions AS (
    SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE d.long_title LIKE '%heart failure%'
),
male_66 AS (
    SELECT p.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE p.gender = 'M' AND p.anchor_age = 66
)
SELECT 
    ha.hadm_id,
    MAX(l.valuenum) AS max_creatinine_first_24h
FROM hf_admissions ha
INNER JOIN male_66 m 
    ON ha.subject_id = m.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON ha.hadm_id = l.hadm_id
    AND l.charttime BETWEEN ha.admittime AND DATETIME_ADD(ha.admittime, INTERVAL 24 HOUR)
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
    AND dl.label = 'Creatinine'
WHERE l.valuenum IS NOT NULL
GROUP BY ha.hadm_id
ORDER BY max_creatinine_first_24h DESC;