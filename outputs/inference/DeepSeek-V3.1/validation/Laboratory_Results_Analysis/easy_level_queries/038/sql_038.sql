WITH stroke_admissions AS (
    SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON diag.icd_code = dicd.icd_code AND diag.icd_version = dicd.icd_version
    WHERE pat.gender = 'M'
        AND pat.anchor_age = 50
        AND dicd.icd_code LIKE 'I63%'  -- Ischemic stroke ICD-10 codes
)
SELECT sa.subject_id, sa.hadm_id, MIN(lab.valuenum) AS min_hemoglobin
FROM stroke_admissions sa
INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON sa.hadm_id = lab.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
    ON lab.itemid = dlab.itemid
WHERE dlab.itemid = 51222  -- Hemoglobin
    AND lab.charttime >= sa.admittime
    AND lab.charttime <= DATETIME_ADD(sa.admittime, INTERVAL 24 HOUR)
    AND lab.valuenum IS NOT NULL
GROUP BY sa.subject_id, sa.hadm_id;