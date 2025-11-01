WITH index_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    a.insurance,
    p.gender,
    p.anchor_age,
    d.long_title AS diagnosis_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
    ON a.hadm_id = d_icd.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON d_icd.icd_code = d.icd_code AND d_icd.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 61 AND 71
    AND a.insurance LIKE '%Medicare%'
    AND a.admission_location LIKE '%SNF%'
    AND d_icd.seq_num = 1
    AND (d.long_title LIKE '%acute kidney injury%' OR d.long_title LIKE '%acute renal failure%')
    AND a.dischtime IS NOT NULL
),
readmission_flag AS (
  SELECT
    i.*,
    CASE WHEN r.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted
  FROM
    index_admissions i
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` r
    ON i.subject_id = r.subject_id
    AND r.admittime > i.dischtime
    AND r.admittime <= DATE_ADD(i.dischtime, INTERVAL 30 DAY)
)
SELECT
  AVG(readmitted) * 100 AS readmission_rate,
  MAX(CASE WHEN readmitted = 1 THEN median_los END) AS median_los_readmitted,
  MAX(CASE WHEN readmitted = 0 THEN median_los END) AS median_los_non_readmitted,
  (COUNTIF(los > 6) * 100.0) / NULLIF(COUNT(*), 0) AS percent_los_gt6
FROM (
  SELECT
    *,
    PERCENTILE_CONT(los, 0.5) OVER (PARTITION BY readmitted) AS median_los
  FROM readmission_flag
) AS subquery;