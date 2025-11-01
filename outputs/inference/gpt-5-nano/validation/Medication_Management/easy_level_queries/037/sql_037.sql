WITH ace_prescriptions AS (
  SELECT
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
   AND p.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON p.subject_id = pat.subject_id
  WHERE
    pat.anchor_age = 55
    AND LOWER(pat.gender) = 'f'
    -- ACE inhibitors (common names)
    AND REGEXP_CONTAINS(LOWER(p.drug),
      r'(lisinopril|enalapril|ramipril|benazepril|captopril|fosinopril|perindopril|quinapril|trandolapril|moexipril)')
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    -- Ensure this corresponds to a real inpatient stay
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- Non-negative durations
    AND TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) >= 0
)
SELECT
  CAST(quantiles[OFFSET(24)] AS FLOAT64) AS p25_duration_days
FROM (
  SELECT APPROX_QUANTILES(duration_days, 100) AS quantiles
  FROM ace_prescriptions
) AS q;