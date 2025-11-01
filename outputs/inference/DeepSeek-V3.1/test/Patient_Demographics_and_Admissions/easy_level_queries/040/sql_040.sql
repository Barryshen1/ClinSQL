WITH stroke_icu_stays AS (
    SELECT DISTINCT
        ie.stay_id,
        ie.los
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON ie.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 35 AND 45
        AND diag.icd_version = 10
        AND (d.icd_code LIKE 'I63%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%' OR d.icd_code LIKE 'I64%')
)
SELECT
    APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_icu_los
FROM stroke_icu_stays;