SELECT
    STDDEV(TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY)) AS stddev_inpatient_nitrate_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON p.subject_id = adm.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON adm.subject_id = pr.subject_id AND adm.hadm_id = pr.hadm_id
WHERE
    p.gender = 'F' -- Filter for female patients
    AND p.anchor_age BETWEEN 73 AND 83 -- Filter for age at anchor_year between 73 and 83
    AND LOWER(pr.drug) LIKE '%nitrate%' -- Identify nitrate-containing drugs (case-insensitive)
    AND pr.starttime IS NOT NULL -- Ensure prescription start time is recorded
    AND pr.stoptime IS NOT NULL -- Ensure prescription stop time is recorded
    AND TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) >= 0 -- Ensure non-negative duration
;