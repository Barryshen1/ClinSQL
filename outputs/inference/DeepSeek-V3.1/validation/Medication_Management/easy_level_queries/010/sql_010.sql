WITH nitrate_prescriptions AS (
    SELECT
        p.subject_id,
        pr.hadm_id,  -- Changed from p.hadm_id to pr.hadm_id
        pr.starttime,
        pr.stoptime,
        DATE_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON p.subject_id = pr.subject_id AND a.hadm_id = pr.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 73 AND 83
        AND LOWER(pr.drug) LIKE '%nitrate%'
        AND pr.starttime IS NOT NULL
        AND pr.stoptime IS NOT NULL
        AND pr.stoptime > pr.starttime
        AND pr.starttime >= a.admittime
        AND pr.stoptime <= a.dischtime
)
SELECT
    STDDEV(duration_days) AS sd_duration_days
FROM nitrate_prescriptions;