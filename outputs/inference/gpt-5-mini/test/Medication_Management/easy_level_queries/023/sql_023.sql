WITH ace_pres AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.drug,
    a.admittime,
    a.dischtime,
    pt.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE pt.gender = 'F'
    AND pt.anchor_age BETWEEN 78 AND 88
    AND p.starttime IS NOT NULL
    -- match common ACE-inhibitor generic names (case-insensitive)
    AND REGEXP_CONTAINS(LOWER(COALESCE(p.drug, '')), r'(lisinopril|enalapril|ramipril|captopril|benazepril|perindopril|moexipril|quinapril|fosinopril|trandolapril)')
)
, durations AS (
  SELECT
    -- duration capped to the admission window, in fractional days
    TIMESTAMP_DIFF(
      LEAST(COALESCE(stoptime, dischtime), dischtime),
      GREATEST(starttime, admittime),
      SECOND
    ) / 86400.0 AS duration_days
  FROM ace_pres
)
SELECT
  STDDEV_SAMP(duration_days) AS sd_days,
  COUNT(*) AS n_prescriptions
FROM durations
WHERE duration_days > 0;