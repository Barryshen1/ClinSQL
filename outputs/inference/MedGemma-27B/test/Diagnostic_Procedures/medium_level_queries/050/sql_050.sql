WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 90 AND 100
),
AdmissionImaging AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNT(p.seq_num) AS imaging_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
    ON a.hadm_id = p.hadm_id
  WHERE
    p.icd_version = 9
    AND p.icd_code LIKE '7%' -- Diagnostic imaging codes in ICD-9 start with 7
  GROUP BY
    a.subject_id,
    a.hadm_id
),
AdmissionLength AS (
  SELECT
    hadm_id,
    (TIMESTAMP_DIFF(dischtime, admittime, DAY) + 1) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE
    dischtime IS NOT NULL
    AND admittime IS NOT NULL
)
SELECT
  CASE
    WHEN al.los BETWEEN 1 AND 3
    THEN '1-3 days'
    WHEN al.los BETWEEN 4 AND 7
    THEN '4-7 days'
    ELSE 'Other'
  END AS los_category,
  AVG(ai.imaging_count) AS mean_imaging,
  MIN(ai.imaging_count) AS min_imaging,
  MAX(ai.imaging_count) AS max_imaging
FROM
  AdmissionImaging AS ai
  INNER JOIN AdmissionLength AS al
  ON ai.hadm_id = al.hadm_id
  INNER JOIN PatientAge AS pa
  ON ai.subject_id = pa.subject_id
GROUP BY
  los_category
ORDER BY
  los_category;