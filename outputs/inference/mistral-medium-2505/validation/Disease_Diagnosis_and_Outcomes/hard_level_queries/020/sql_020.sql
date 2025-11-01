WITH
-- Get male patients aged 46-56
male_patients AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 46 AND 56
),

-- Get AMI admissions (ICD-9: 410.xx, ICD-10: I21.x)
ami_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    d.icd_code,
    d.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    (d.icd_version = 9 AND d.icd_code LIKE '410.%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I21.%')
),

-- Get major complications (example: cardiac arrest, shock, etc.)
major_complications AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    COUNT(DISTINCT
      CASE
        WHEN (di.icd_version = 9 AND di.icd_code IN ('427.5', '785.51', '995.92'))
          OR (di.icd_version = 10 AND di.icd_code IN ('I46.9', 'R57.9', 'T81.19'))
        THEN di.icd_code
      END
    ) AS complication_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY
    di.subject_id, di.hadm_id
),

-- Combine data and calculate composite score
patient_scores AS (
  SELECT
    m.subject_id,
    a.hadm_id,
    m.anchor_age,
    COALESCE(mc.complication_count, 0) AS complication_count,
    m.anchor_age + COALESCE(mc.complication_count, 0) AS composite_score,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM
    male_patients m
  JOIN
    ami_admissions a ON m.subject_id = a.subject_id
  LEFT JOIN
    major_complications mc ON m.subject_id = mc.subject_id AND a.hadm_id = mc.hadm_id
),

-- Assign quintiles
quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY composite_score) AS quintile
  FROM
    patient_scores
),

-- Calculate median LOS per quintile
quintile_stats AS (
  SELECT
    quintile,
    PERCENTILE_CONT(CASE WHEN hospital_expire_flag = 0 THEN los_days ELSE NULL END, 0.5)
      OVER(PARTITION BY quintile) AS median_los_survivors
  FROM
    quintiles
)

-- Final aggregation
SELECT
  q.quintile,
  COUNT(*) AS patient_count,
  ROUND(100 * SUM(CASE WHEN q.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS mortality_pct,
  ROUND(100 * SUM(CASE WHEN q.complication_count > 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS complication_pct,
  ROUND(MAX(qs.median_los_survivors), 1) AS median_los_survivors
FROM
  quintiles q
JOIN
  quintile_stats qs ON q.quintile = qs.quintile
GROUP BY
  q.quintile
ORDER BY
  q.quintile;