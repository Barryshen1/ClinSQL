WITH stroke_admissions AS (
  SELECT
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND d.seq_num = 1
    AND d.icd_version = 10
    AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%')
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND p.anchor_year IS NOT NULL
    AND p.anchor_age IS NOT NULL
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 37 AND 47
)
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los_days
FROM
  stroke_admissions;