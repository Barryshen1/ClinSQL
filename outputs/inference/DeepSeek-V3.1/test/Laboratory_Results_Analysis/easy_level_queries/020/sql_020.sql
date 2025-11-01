WITH hf_admissions AS (
    SELECT DISTINCT adm.subject_id, adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE p.gender = 'M'
        AND p.anchor_age = 49
        AND diag.icd_version = 10
        AND d.icd_code LIKE 'I50%'
),
nadir_hgb_per_admission AS (
    SELECT ha.hadm_id, MIN(le.valuenum) AS nadir_hgb
    FROM hf_admissions ha
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ha.hadm_id = le.hadm_id
    WHERE le.itemid = 51222  -- Hemoglobin
        AND le.valuenum IS NOT NULL
        AND le.valuenum > 0  -- reasonable value filter
    GROUP BY ha.hadm_id
)
SELECT APPROX_QUANTILES(nadir_hgb, 100)[OFFSET(75)] AS percentile_75_nadir_hgb
FROM nadir_hgb_per_admission;