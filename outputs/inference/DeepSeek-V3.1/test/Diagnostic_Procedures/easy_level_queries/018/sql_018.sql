WITH cohort AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M'
    AND anchor_age BETWEEN 86 AND 96
),
proc_counts AS (
    SELECT 
        cohort.subject_id,
        COUNT(DISTINCT proc.icd_code) AS num_procedures
    FROM cohort
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
        ON cohort.subject_id = proc.subject_id
        AND proc.icd_version = 10
        AND (proc.icd_code LIKE '025%' OR proc.icd_code = '5A2204Z')
    GROUP BY cohort.subject_id
)
SELECT 
    STDDEV(num_procedures) AS sd_distinct_procedures_per_patient
FROM proc_counts;