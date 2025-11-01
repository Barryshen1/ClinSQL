SELECT
  STDDEV_SAMP(duration_days) AS sd_prescription_duration_days
FROM (
  SELECT
    p.subject_id,
    p.hadm_id,
    -- Calculate duration in days between start and stop times
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pt
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS p
    ON pt.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON p.subject_id = pr.subject_id
    AND p.hadm_id = pr.hadm_id
  WHERE
    -- Female patients aged 78–88
    pt.gender = 'F'
    AND pt.anchor_age BETWEEN 78 AND 88
    -- Inpatient prescriptions
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    -- Filter for ACE-inhibitors (drug names ending in "pril")
    AND LOWER(pr.drug) LIKE '%pril%'
    -- Ensure the prescription falls within the hospital admission window
    AND pr.starttime BETWEEN p.admittime AND p.dischtime
    AND pr.stoptime BETWEEN p.admittime AND p.dischtime
);