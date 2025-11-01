WITH cohort AS (
  -- hospitalized male patients aged 82-92
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME(a.admittime) AS admittime,
    DATETIME(a.dischtime) AS dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    USING(subject_id)
  WHERE pt.gender = 'M'
    AND pt.anchor_age BETWEEN 82 AND 92
),

digoxin_rx AS (
  -- prescriptions for digoxin (including common brand "lanoxin"),
  -- restricted to orders that have both start and stop within the hospitalization
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.drug,
    DATETIME_DIFF(p.stoptime, p.starttime, SECOND) / 86400.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN cohort c
    USING(subject_id, hadm_id)
  WHERE p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.starttime >= c.admittime
    AND p.starttime <= c.dischtime
    AND p.stoptime >= p.starttime
    AND (
      LOWER(COALESCE(p.drug, '')) LIKE '%digoxin%'
      OR LOWER(COALESCE(p.drug, '')) LIKE '%lanoxin%'
    )
)

-- Final: longest single inpatient digoxin prescription duration (days)
SELECT
  ROUND(MAX(duration_days), 3) AS longest_digoxin_prescription_days
FROM digoxin_rx;