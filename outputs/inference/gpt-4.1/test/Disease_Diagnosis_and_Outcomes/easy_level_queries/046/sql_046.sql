SELECT
  STDDEV_SAMP(los_days) AS sd_hospital_los_days
FROM (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND d.seq_num = 1
    AND (
      -- ICD-10 hemorrhagic stroke
      (d.icd_version = 10 AND (
        LEFT(d.icd_code, 3) IN ('I60', 'I61', 'I62')
      ))
      -- ICD-9 hemorrhagic stroke
      OR (d.icd_version = 9 AND (
        LEFT(d.icd_code, 3) IN ('430', '431', '432')
      ))
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) > 0
);