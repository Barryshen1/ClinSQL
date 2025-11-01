WITH HeartFailureAdmissions AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON adm.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d_icd
        ON adm.subject_id = d_icd.subject_id AND adm.hadm_id = d_icd.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age = 65
        AND (
            (d_icd.icd_version = 10 AND d_icd.icd_code LIKE 'I50%') OR -- ICD-10 codes for Heart Failure
            (d_icd.icd_version = 9 AND d_icd.icd_code LIKE '428%')    -- ICD-9 codes for Heart Failure
        )
)
-- Find the minimum serum sodium value from all identified heart failure admissions
SELECT
    MIN(le.valuenum) AS min_admission_serum_sodium
FROM
    HeartFailureAdmissions AS hfa
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON hfa.subject_id = le.subject_id AND hfa.hadm_id = le.hadm_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
WHERE
    -- Specific itemids for Sodium in blood/serum (based on d_labitems lookup)
    le.itemid IN (50983, 50824) -- 50983: Sodium, Bld; 50824: Sodium
    AND le.valuenum IS NOT NULL -- Ensure a numeric value exists
    AND le.valuenum > 0         -- Sodium levels are physiologically positive
;