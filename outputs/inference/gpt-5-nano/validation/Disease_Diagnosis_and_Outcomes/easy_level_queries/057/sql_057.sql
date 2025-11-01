WITH pneumonia_primary AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND di.seq_num = 1
    AND di.icd_version = 9
    AND di.icd_code IN ('480','481','482','483','484','485','486')
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  MIN(los_days) AS min_los_days
FROM pneumonia_primary;