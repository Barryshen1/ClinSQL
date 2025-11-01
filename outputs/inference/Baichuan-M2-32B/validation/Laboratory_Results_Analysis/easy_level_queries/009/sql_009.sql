WITH female_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F'
),
acs_admissions AS (
    SELECT 
        a.subject_id, 
        a.hadm_id,
        a.admittime,
        a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN female_patients f ON a.subject_id = f.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.hadm_id = d.hadm_id
    WHERE d.icd_code LIKE 'I20%' 
        OR d.icd_code LIKE 'I21%' 
        OR d.icd_code LIKE 'I22%'
        AND d.icd_version = 10
),
troponin_itemids AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE label LIKE '%troponin%'
),
admission_troponin AS (
    SELECT 
        a.hadm_id,
        MIN(l.valuenum) AS nadir_troponin
    FROM acs_admissions a
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
        ON a.hadm_id = l.hadm_id
    JOIN troponin_itemids t ON l.itemid = t.itemid
    WHERE l.charttime >= a.admittime 
        AND (a.dischtime IS NULL OR l.charttime <= a.dischtime)
        AND l.valuenum IS NOT NULL
    GROUP BY a.hadm_id
)
SELECT 
    APPROX_QUANTILES(nadir_troponin, 100)[OFFSET(25)] AS p25_nadir_troponin
FROM admission_troponin;