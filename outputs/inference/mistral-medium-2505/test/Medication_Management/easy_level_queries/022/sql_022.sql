WITH female_patients_59_69 AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Calculate age at admission (approximate)
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 59 AND 69
),

ccb_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug,
    p.starttime,
    p.stoptime,
    -- Calculate duration in hours
    TIMESTAMP_DIFF(p.stoptime, p.starttime, HOUR) AS duration_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    female_patients_59_69 fp
  ON
    p.subject_id = fp.subject_id AND p.hadm_id = fp.hadm_id
  WHERE
    -- Filter for dihydropyridine CCBs (common examples)
    LOWER(p.drug) LIKE '%amlodipine%'
    OR LOWER(p.drug) LIKE '%nifedipine%'
    OR LOWER(p.drug) LIKE '%felodipine%'
    OR LOWER(p.drug) LIKE '%nicardipine%'
    OR LOWER(p.drug) LIKE '%isradipine%'
    -- Ensure prescription has a valid stop time
    AND p.stoptime IS NOT NULL
    -- Ensure prescription was during inpatient stay
    AND p.starttime BETWEEN fp.admittime AND fp.dischtime
)

SELECT
  PERCENTILE_CONT(duration_hours, 0.5) OVER() AS median_duration_hours
FROM
  ccb_prescriptions
LIMIT 1;