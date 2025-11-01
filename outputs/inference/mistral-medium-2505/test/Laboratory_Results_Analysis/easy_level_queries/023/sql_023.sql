WITH sepsis_patients AS (
  -- Identify male patients with sepsis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime,
    DATE(a.dischtime) AS discharge_date
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND (
      -- ICD-9 codes for sepsis
      (d.icd_version = 9 AND d.icd_code IN ('99591', '99592', '78552'))
      OR
      -- ICD-10 codes for sepsis
      (d.icd_version = 10 AND d.icd_code IN ('R6520', 'R6521'))
    )
    AND a.deathtime IS NULL -- Ensure patient is alive on discharge
),

lactate_measurements AS (
  -- Get serum lactate measurements on discharge day
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    sepsis_patients sp
    ON l.subject_id = sp.subject_id AND l.hadm_id = sp.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE
    d.label = 'Lactate'
    AND DATE(l.charttime) = sp.discharge_date
)

-- Calculate IQR (25th and 75th percentiles)
SELECT
  PERCENTILE_CONT(lm.valuenum, 0.25) OVER() AS q1,
  PERCENTILE_CONT(lm.valuenum, 0.75) OVER() AS q3,
  PERCENTILE_CONT(lm.valuenum, 0.75) OVER() - PERCENTILE_CONT(lm.valuenum, 0.25) OVER() AS iqr
FROM
  lactate_measurements lm
LIMIT 1;