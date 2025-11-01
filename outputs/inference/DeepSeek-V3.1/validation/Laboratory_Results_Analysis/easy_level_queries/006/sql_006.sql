WITH cohd_patients AS (
    SELECT DISTINCT p.subject_id, p.anchor_age, d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON p.subject_id = d.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
        ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
    WHERE p.anchor_age = 50
        AND p.gender = 'F'
        AND (
            (d.icd_version = 10 AND diag.icd_code LIKE 'J44%')
            OR (d.icd_version = 9 AND diag.icd_code LIKE '491%')
            OR (d.icd_version = 9 AND diag.icd_code LIKE '492%')
            OR (d.icd_version = 9 AND diag.icd_code = '496')
        )
),
sodium_labs AS (
    SELECT subject_id, hadm_id, valuenum
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE dli.label LIKE '%sodium%'
        AND dli.fluid = 'Blood'
        AND le.valuenum IS NOT NULL
),
nadir_per_admission AS (
    SELECT cp.subject_id, cp.hadm_id, MIN(sl.valuenum) AS nadir_sodium
    FROM cohd_patients cp
    INNER JOIN sodium_labs sl
        ON cp.subject_id = sl.subject_id AND cp.hadm_id = sl.hadm_id
    GROUP BY cp.subject_id, cp.hadm_id
)
SELECT STDDEV(nadir_sodium) AS std_dev_nadir_sodium
FROM nadir_per_admission;