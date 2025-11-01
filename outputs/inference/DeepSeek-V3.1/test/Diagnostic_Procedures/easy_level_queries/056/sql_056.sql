WITH female_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F'
    AND anchor_age BETWEEN 43 AND 53
),
procedures AS (
    SELECT 
        fp.subject_id,
        proc.icd_code
    FROM female_patients fp
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
        ON fp.subject_id = proc.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
        ON proc.icd_code = dicd.icd_code AND proc.icd_version = dicd.icd_version
    WHERE proc.icd_version = 10
    AND proc.icd_code LIKE '5A0%'
),
distinct_proc_counts AS (
    SELECT
        subject_id,
        COUNT(DISTINCT icd_code) AS num_distinct_procedures
    FROM procedures
    GROUP BY subject_id
)
SELECT
    APPROX_QUANTILES(num_distinct_procedures, 100)[OFFSET(25)] AS percentile_25
FROM distinct_proc_counts;