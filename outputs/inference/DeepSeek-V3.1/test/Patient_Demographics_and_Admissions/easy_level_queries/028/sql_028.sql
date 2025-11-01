WITH sepsis_stays AS (
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
        p.gender = 'M'
        AND p.anchor_age BETWEEN 90 AND 100
        AND (
            (diag.icd_version = 9 AND (d.icd_code LIKE '038%' OR d.icd_code LIKE '995.92%'))
            OR
            (diag.icd_version = 10 AND (d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'R65.2%'))
        )
)
SELECT
    STDDEV(los) AS los_stddev
FROM sepsis_stays;