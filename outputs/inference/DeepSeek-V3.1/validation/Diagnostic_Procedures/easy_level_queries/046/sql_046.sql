WITH cohort AS (
    SELECT p.subject_id, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 80 AND 90
),

mcs_procedures AS (
    SELECT subject_id, hadm_id, icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE icd_version = 10
        AND icd_code IN (
            '5A1522H', -- ECMO
            '5A1522G', -- ECMO
            '4A02EK3', -- IABP
            '02HA0RS', -- VAD
            '02HA0RJ', -- VAD
            '02HA0QZ', -- VAD
            '5A0221D'  -- Percutaneous external heart assist
        )
),

counts_per_admission AS (
    SELECT c.subject_id, c.hadm_id, COUNT(DISTINCT mp.icd_code) AS num_mcs_procedures
    FROM cohort c
    LEFT JOIN mcs_procedures mp
        ON c.hadm_id = mp.hadm_id
    GROUP BY c.subject_id, c.hadm_id
)

SELECT MAX(num_mcs_procedures) AS max_mcs_procedures_per_patient
FROM counts_per_admission
;