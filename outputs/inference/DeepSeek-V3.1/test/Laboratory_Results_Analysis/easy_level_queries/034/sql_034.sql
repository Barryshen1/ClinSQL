WITH hf_admissions AS (
    SELECT DISTINCT adm.subject_id, adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE pat.gender = 'M'
        AND pat.anchor_age = 65
        AND (d.icd_code LIKE 'I50%' OR d.icd_code LIKE '428%')
),
sodium_labs AS (
    SELECT ha.subject_id, ha.hadm_id, MIN(le.valuenum) AS min_sodium
    FROM hf_admissions ha
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ha.hadm_id = le.hadm_id AND ha.subject_id = le.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE dli.itemid = 50824  -- Sodium
        AND le.valuenum IS NOT NULL
    GROUP BY ha.subject_id, ha.hadm_id
)
SELECT MIN(min_sodium) AS overall_min_sodium
FROM sodium_labs;