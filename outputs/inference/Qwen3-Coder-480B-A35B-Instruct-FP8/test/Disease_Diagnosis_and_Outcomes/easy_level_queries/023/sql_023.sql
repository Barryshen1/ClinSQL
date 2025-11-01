SELECT
  APPROX_QUANTILES(
    DATETIME_DIFF(dischtime, admittime, HOUR), 2
  )[OFFSET(1)] AS median_los_hours
FROM
  physionet-data.mimiciv_3_1_hosp.admissions a
JOIN
  physionet-data.mimiciv_3_1_hosp.patients p
  ON a.subject_id = p.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
  ON d.icd_code = dd.icd_code
  AND d.icd_version = dd.icd_version
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 83 AND 93
  AND d.seq_num = 1
  AND (
    (d.icd_version = 9 AND d.icd_code = '486')
    OR
    (d.icd_version = 10 AND d.icd_code = 'J189')
  )
  AND a.dischtime IS NOT NULL;