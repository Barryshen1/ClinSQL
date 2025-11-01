WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admit,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 46 AND 56
),

ami_admissions AS (
  SELECT DISTINCT
    c.*
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    c.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    (d.icd_version = 9 AND dd.icd_code LIKE '410%')
    OR
    (d.icd_version = 10 AND dd.icd_code LIKE 'I21%')
),

complications AS (
  SELECT
    d.hadm_id,
    COUNT(*) AS complication_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    (d.icd_version = 9 AND dd.icd_code IN ('428.0', '428.1', '428.9', '785.51', '785.59', '427.1', '427.41', '427.5'))
    OR
    (d.icd_version = 10 AND dd.icd_code IN ('I50.9', 'I50.1', 'I50.20', 'I50.21', 'I50.22', 'I50.23', 'I50.30', 'I50.31', 'I50.32', 'I50.33', 'I50.40', 'I50.41', 'I50.42', 'I50.43', 'R57.0', 'I46.0', 'I46.1', 'I46.2', 'I46.8', 'I46.9', 'I47.1', 'I47.2', 'I49.01', 'I49.02'))
  GROUP BY
    d.hadm_id
),

risk_scores AS (
  SELECT
    a.*,
    COALESCE(c.complication_count, 0) AS complication_count,
    a.age_at_admit + COALESCE(c.complication_count, 0) AS risk_score
  FROM
    ami_admissions a
  LEFT JOIN
    complications c
  ON
    a.hadm_id = c.hadm_id
),

quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS risk_quintile
  FROM
    risk_scores
)

SELECT
  risk_quintile,
  COUNT(*) AS patient_count,
  AVG(hospital_expire_flag) * 100 AS mortality_percent,
  AVG(CASE WHEN complication_count > 0 THEN 1 ELSE 0 END) * 100 AS complication_percent,
  APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_days ELSE NULL END, 2)[OFFSET(1)] AS median_survivor_los
FROM
  quintiles
GROUP BY
  risk_quintile
ORDER BY
  risk_quintile;