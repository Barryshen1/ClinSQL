WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    d.seq_num = 1
    AND p.gender = 'M'
    AND p.anchor_age = 70
    AND (
      di.long_title LIKE '%upper GI bleeding%'
      OR di.long_title LIKE '%upper gastrointestinal bleeding%'
      OR di.long_title LIKE '%gastrointestinal haemorrhage upper%'
      OR di.long_title LIKE '%upper GI bleed%'
    )
)
SELECT
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los_days) AS percentile_75
FROM
  filtered_admissions;