WITH male_inpatients_64_74 AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.drug,
    -- Calculate age at admission (anchor_age is age at first admission)
    EXTRACT(YEAR FROM a.admittime) - (pat.anchor_year - pat.anchor_age) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON
    p.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - (pat.anchor_year - pat.anchor_age)) BETWEEN 64 AND 74
    AND LOWER(p.drug) IN ('spironolactone', 'eplerenone')
    AND p.stoptime IS NOT NULL  -- Exclude ongoing prescriptions
),

prescription_durations AS (
  SELECT
    subject_id,
    hadm_id,
    drug,
    -- Calculate duration in days
    TIMESTAMP_DIFF(stoptime, starttime, DAY) AS duration_days
  FROM
    male_inpatients_64_74
)

SELECT
  drug,
  AVG(duration_days) AS avg_duration_days,
  COUNT(*) AS num_prescriptions
FROM
  prescription_durations
GROUP BY
  drug
ORDER BY
  drug;