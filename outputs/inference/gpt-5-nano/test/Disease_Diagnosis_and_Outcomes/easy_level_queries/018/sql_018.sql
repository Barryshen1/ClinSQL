WITH coh AS (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id
    AND a.hadm_id = di.hadm_id
  WHERE
    di.seq_num = 1
    AND (
      (di.icd_version = 10 AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%'))
      OR
      (di.icd_version = 9 AND (di.icd_code LIKE '430%' OR di.icd_code LIKE '431%' OR di.icd_code LIKE '432%'))
    )
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND a.dischtime > a.admittime
)
SELECT
  STDDEV_SAMP(los_days) AS sd_los_days
FROM coh;