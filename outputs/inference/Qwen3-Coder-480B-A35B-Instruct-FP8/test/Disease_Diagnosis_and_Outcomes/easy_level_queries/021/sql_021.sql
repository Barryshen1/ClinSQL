WITH hemorrhagic_stroke_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d1
    ON a.hadm_id = d1.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd1
    ON d1.icd_code = dd1.icd_code AND d1.icd_version = dd1.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND d1.seq_num = 1
    AND (
      (d1.icd_version = 9 AND d1.icd_code IN ('430', '431', '432'))
      OR
      (d1.icd_version = 10 AND d1.icd_code IN ('I60', 'I61', 'I62'))
    )
),
copd_admissions AS (
  SELECT DISTINCT
    d2.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d2
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd2
    ON d2.icd_code = dd2.icd_code AND d2.icd_version = dd2.icd_version
  WHERE
    d2.seq_num > 1
    AND (
      (d2.icd_version = 9 AND d2.icd_code IN ('49121', '49122', '496'))
      OR
      (d2.icd_version = 10 AND d2.icd_code = 'J441')
    )
)
SELECT
  APPROX_QUANTILES(los_days, 4)[ORDINAL(2)] AS q1,
  APPROX_QUANTILES(los_days, 4)[ORDINAL(3)] AS median,
  APPROX_QUANTILES(los_days, 4)[ORDINAL(4)] AS q3
FROM
  hemorrhagic_stroke_admissions hsa
JOIN
  copd_admissions ca
  ON hsa.hadm_id = ca.hadm_id;