WITH HeartFailureAdmissions AS (
    -- Select unique admission IDs where the primary diagnosis is heart failure
    SELECT DISTINCT
        diag.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
        ON diag.icd_code = ddx.icd_code AND diag.icd_version = ddx.icd_version
    WHERE
        diag.seq_num = 1 -- Primary diagnosis
        AND LOWER(ddx.long_title) LIKE '%heart failure%' -- Cases related to heart failure
)
SELECT
    -- Calculate the average hospital length of stay in days
    AVG(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) AS average_hospital_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pa
JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pa.subject_id = adm.subject_id
JOIN
    HeartFailureAdmissions AS hfa
    ON adm.hadm_id = hfa.hadm_id
WHERE
    pa.gender = 'F' -- Filter for female patients
    AND pa.anchor_age BETWEEN 61 AND 71; -- Filter for age range 61-71 years old;