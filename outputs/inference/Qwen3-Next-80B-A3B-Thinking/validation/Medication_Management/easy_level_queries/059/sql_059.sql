WITH filtered_prescriptions AS (
    SELECT
        pr.stoptime,
        pr.starttime,
        TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON pr.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON pr.hadm_id = a.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 38 AND 48
        AND (
            LOWER(pr.drug) LIKE '%losartan%'
            OR LOWER(pr.drug) LIKE '%valsartan%'
            OR LOWER(pr.drug) LIKE '%irbesartan%'
            OR LOWER(pr.drug) LIKE '%candesartan%'
            OR LOWER(pr.drug) LIKE '%telmisartan%'
            OR LOWER(pr.drug) LIKE '%eprosartan%'
            OR LOWER(pr.drug) LIKE '%azilsartan%'
            OR LOWER(pr.drug) LIKE '%olmesartan%'
        )
        AND pr.stoptime IS NOT NULL
        AND pr.stoptime > pr.starttime
        AND pr.starttime >= a.admittime
        AND pr.stoptime <= a.dischtime
)
SELECT
    PERCENTILE_CONT(duration, 0.75) OVER() AS percentile_75
FROM filtered_prescriptions
LIMIT 1;