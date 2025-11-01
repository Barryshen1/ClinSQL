WITH female_41_51 AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' 
      AND anchor_age BETWEEN 41 AND 51
),
cabg_codes AS (
    SELECT DISTINCT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE 
        LOWER(long_title) LIKE '%coronary artery bypass%' 
        OR LOWER(long_title) LIKE '%cabg%' 
        OR LOWER(long_title) LIKE '%coronary bypass%'
),
cabg_procedures AS (
    SELECT proc.subject_id, COUNT(*) AS cabg_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    INNER JOIN cabg_codes c 
        ON proc.icd_code = c.icd_code 
        AND proc.icd_version = c.icd_version
    GROUP BY proc.subject_id
),
cohort AS (
    SELECT 
        f.subject_id, 
        COALESCE(cp.cabg_count, 0) AS cabg_count
    FROM female_41_51 f
    LEFT JOIN cabg_procedures cp 
        ON f.subject_id = cp.subject_id
)
SELECT STDDEV_POP(cabg_count) AS std_dev_cabg_per_patient
FROM cohort;