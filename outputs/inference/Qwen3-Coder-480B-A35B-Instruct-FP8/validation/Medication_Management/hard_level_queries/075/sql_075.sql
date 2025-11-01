WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
),

-- Identify COPD admissions using ICD codes
copd_admissions AS (
  SELECT DISTINCT
    c.*
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    c.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%copd%'
    OR LOWER(d.long_title) LIKE '%chronic obstructive pulmonary disease%'
),

-- Medication complexity: count distinct drugs in first 72h
med_complexity AS (
  SELECT
    ca.hadm_id,
    COUNT(DISTINCT pr.drug) AS complexity_score
  FROM
    copd_admissions ca
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON
    ca.hadm_id = pr.hadm_id
  WHERE
    pr.starttime >= ca.admittime
    AND pr.starttime <= DATETIME_ADD(ca.admittime, INTERVAL 72 HOUR)
  GROUP BY
    ca.hadm_id
),

-- Combine admissions with complexity scores
admissions_with_complexity AS (
  SELECT
    ca.*,
    mc.complexity_score
  FROM
    copd_admissions ca
  JOIN
    med_complexity mc
  ON
    ca.hadm_id = mc.hadm_id
),

-- Assign tertiles
tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM
    admissions_with_complexity
),

-- Detect 30-day readmission
readmissions AS (
  SELECT
    t1.*,
    CASE
      WHEN t2.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS readmit_30day
  FROM
    tertiles t1
  LEFT JOIN
    tertiles t2
  ON
    t1.subject_id = t2.subject_id
    AND t2.admittime > t1.dischtime
    AND DATETIME_DIFF(t2.admittime, t1.dischtime, DAY) <= 30
),

-- Aggregate by tertile
final_stats AS (
  SELECT
    tertile,
    COUNT(*) AS n,
    MIN(complexity_score) AS min_complexity,
    MAX(complexity_score) AS max_complexity,
    AVG(complexity_score) AS mean_complexity,
    AVG(los_days) AS mean_los,
    AVG(hospital_expire_flag) * 100 AS mortality_pct,
    AVG(readmit_30day) * 100 AS readmit_30day_pct
  FROM
    readmissions
  GROUP BY
    tertile
)

SELECT
  tertile,
  n,
  min_complexity,
  max_complexity,
  ROUND(mean_complexity, 2) AS mean_complexity,
  ROUND(mean_los, 2) AS mean_los,
  ROUND(mortality_pct, 2) AS mortality_pct,
  ROUND(readmit_30day_pct, 2) AS readmit_30day_pct
FROM
  final_stats
ORDER BY
  tertile;