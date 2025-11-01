WITH AdmissionsFiltered AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON adm.subject_id = di.subject_id AND adm.hadm_id = di.hadm_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 73 AND 83
        AND di.seq_num = 1 -- Primary diagnosis
        AND (
               di.icd_code LIKE 'E10.1%'  -- Type 1 diabetes with ketoacidosis
            OR di.icd_code LIKE 'E11.1%'  -- Type 2 diabetes with ketoacidosis
            OR di.icd_code LIKE 'E13.1%'  -- Other specified diabetes mellitus with ketoacidosis
            OR di.icd_code LIKE 'E10.64%' -- Type 1 diabetes with hyperglycemia with hyperosmolarity (HHS)
            OR di.icd_code LIKE 'E11.64%' -- Type 2 diabetes with hyperglycemia with hyperosmolarity (HHS)
            OR di.icd_code LIKE 'E13.64%' -- Other specified diabetes mellitus with hyperglycemia with hyperosmolarity (HHS)
        )
    -- Ensure valid admission and discharge times for LOS calculation
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
    AND adm.dischtime > adm.admittime
),
CalculatedLOS AS (
    SELECT
        DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days
    FROM
        AdmissionsFiltered
)
SELECT
    PERCENTILE_CONT(los_days, 0.25) OVER () AS los_25th_percentile_days
FROM
    CalculatedLOS
LIMIT 1;