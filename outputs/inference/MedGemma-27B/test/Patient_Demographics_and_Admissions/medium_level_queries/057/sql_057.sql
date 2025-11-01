WITH ICUAdmissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.discharge_location,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
      ON a.hadm_id = i.hadm_id
  WHERE
    a.subject_id = 45 -- Specific patient ID
)
SELECT
  CASE
    WHEN a.deathtime IS NOT NULL THEN 'In-hospital death'
    WHEN a.discharge_location = 'HOME' THEN 'Home'
    WHEN a.discharge_location = 'HOSPICE' THEN 'Hospice'
    ELSE 'Other'
  END AS discharge_outcome,
  PERCENTILE_CONT(i.los, 0.5) AS p50,
  PERCENTILE_CONT(i.los, 0.75) AS p75,
  PERCENTILE_CONT(i.los, 0.9) AS p90,
  PERCENTILE_CONT(i.los, 0.95) AS p95,
  COUNT(CASE WHEN i.los <= 7 THEN 1 END) * 100.0 / COUNT(i.los) AS pct_le_7_days
FROM
  ICUAdmissions AS i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 40 AND 50
  AND a.subject_id = 45 -- Ensure patient ID filter is applied correctly
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;