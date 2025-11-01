WITH female_patients_73_83 AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.anchor_year,
    TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year, 1, 1), YEAR) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year, 1, 1), YEAR) BETWEEN 73 AND 83
),

nitrate_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    female_patients_73_83 fp ON p.subject_id = fp.subject_id AND p.hadm_id = fp.hadm_id
  WHERE
    p.stoptime IS NOT NULL
    AND p.starttime IS NOT NULL
    AND p.stoptime > p.starttime
    AND (
      LOWER(p.drug) LIKE '%nitrate%'
      OR LOWER(p.drug) LIKE '%nitroglycerin%'
      OR LOWER(p.drug) LIKE '%isosorbide%'
    )
)

SELECT
  STDDEV(duration_days) AS sd_nitrate_prescription_duration_days
FROM
  nitrate_prescriptions;