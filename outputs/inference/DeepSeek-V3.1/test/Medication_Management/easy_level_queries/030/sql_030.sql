WITH amiodarone_prescriptions AS (
    SELECT
        p.subject_id,
        DATETIME_DIFF(pr.stoptime, pr.starttime, HOUR) AS duration_hours
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON pr.subject_id = p.subject_id
    WHERE
        LOWER(pr.drug) LIKE '%amiodarone%'
        AND p.gender = 'F'
        AND p.anchor_age BETWEEN 42 AND 52
        AND pr.hadm_id IS NOT NULL  -- Ensure inpatient
        AND pr.stoptime IS NOT NULL  -- Must have end time
        AND pr.starttime < pr.stoptime  -- Valid time range
)
SELECT
    PERCENTILE_CONT(duration_hours, 0.25) OVER() AS percentile_25_duration_hours
FROM amiodarone_prescriptions
LIMIT 1;