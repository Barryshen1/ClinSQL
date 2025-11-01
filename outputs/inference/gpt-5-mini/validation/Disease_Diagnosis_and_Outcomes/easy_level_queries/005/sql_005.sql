WITH primary_dx AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender,
    d.icd_code,
    d.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    d.seq_num = 1  -- primary diagnosis
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- ischemic stroke definitions (ICD-10 I63.*, ICD-9 433*, 434*, 436)
    AND (
      (d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) = 'I63')
      OR (d.icd_version = 9 AND (SUBSTR(d.icd_code, 1, 3) IN ('433','434') OR d.icd_code = '436'))
    )
),
cohort_los AS (
  SELECT
    hadm_id,
    -- LOS in fractional days
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days
  FROM primary_dx
  WHERE TIMESTAMP_DIFF(dischtime, admittime, SECOND) >= 0
)
SELECT
  -- median (NULL if no admissions), and number of admissions
  IF(
    arr IS NULL,
    NULL,
    IF(
      MOD(ARRAY_LENGTH(arr), 2) = 1,
      arr[ORDINAL(CAST((ARRAY_LENGTH(arr) + 1) / 2 AS INT64))],
      (
        arr[ORDINAL(CAST(ARRAY_LENGTH(arr) / 2 AS INT64))]
        + arr[ORDINAL(CAST(ARRAY_LENGTH(arr) / 2 AS INT64) + 1)]
      ) / 2.0
    )
  ) AS median_los_days,
  IFNULL(ARRAY_LENGTH(arr), 0) AS n_admissions
FROM (
  SELECT ARRAY_AGG(los_days ORDER BY los_days) AS arr
  FROM cohort_los
);