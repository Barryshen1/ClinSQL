SELECT
  STDDEV(los) AS sd_los_days
FROM (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    diag.seq_num = 1  -- Primary diagnosis
    AND (
      (diag.icd_version = 9 AND SUBSTR(diag.icd_code, 1, 3) IN ('430', '431', '432'))
      OR
      (diag.icd_version = 10 AND SUBSTR(diag.icd_code, 1, 3) IN ('I60', 'I61', 'I62'))
    )
    AND p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 43 AND 53
    AND a.dischtime >= a.admittime  -- Ensure valid LOS
) AS t;