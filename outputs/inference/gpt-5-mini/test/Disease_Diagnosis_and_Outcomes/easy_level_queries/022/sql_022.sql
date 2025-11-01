WITH ischemic_primary_adms AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) / 1440.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dgn
    ON a.subject_id = dgn.subject_id AND a.hadm_id = dgn.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON dgn.icd_code = d.icd_code AND dgn.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND dgn.seq_num = 1  -- primary diagnosis
    AND (
      LOWER(d.long_title) LIKE '%ischemic%'
      OR LOWER(d.long_title) LIKE '%infarct%'
      OR dgn.icd_code LIKE 'I63%'   -- ICD-10 cerebral infarction
      OR dgn.icd_code LIKE '433%'   -- ICD-9 occlusion w/ infarct
      OR dgn.icd_code LIKE '434%'   -- ICD-9 occlusion of cerebral arteries
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)

SELECT
  stats.n_admissions,
  stats.quantiles[OFFSET(25)] AS p25_los_days,
  stats.quantiles[OFFSET(75)] AS p75_los_days,
  stats.quantiles[OFFSET(75)] - stats.quantiles[OFFSET(25)] AS iqr_los_days
FROM (
  SELECT
    COUNT(*) AS n_admissions,
    APPROX_QUANTILES(los_days, 101) AS quantiles
  FROM
    ischemic_primary_adms
) AS stats;