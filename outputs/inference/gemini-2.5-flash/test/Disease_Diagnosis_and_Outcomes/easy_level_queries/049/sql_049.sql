SELECT
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY DATETIME_DIFF(t1.dischtime, t1.admittime, DAY)) AS los_25th_percentile_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS t1
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS t2
    ON t1.subject_id = t2.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS t3
    ON t1.hadm_id = t3.hadm_id
WHERE
    t2.gender = 'F' -- Filter for female patients
    AND (t2.anchor_age + (EXTRACT(YEAR FROM t1.admittime) - t2.anchor_year)) BETWEEN 50 AND 60 -- Filter for age at admission between 50 and 60
    AND t3.seq_num = 1 -- Filter for primary diagnosis
    AND (
        (t3.icd_version = 10 AND t3.icd_code LIKE 'I63%') -- ICD-10 codes for Ischemic Stroke
        OR
        (t3.icd_version = 9 AND t3.icd_code LIKE '434%') -- ICD-9 codes for Ischemic Stroke
    )
    AND t1.dischtime IS NOT NULL; -- Ensure discharge time exists to calculate LOS;