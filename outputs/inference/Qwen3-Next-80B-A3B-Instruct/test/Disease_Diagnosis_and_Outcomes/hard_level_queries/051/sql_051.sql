WITH pancreatitis_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
    AND (
      (d_icd.icd_version = 9 AND d_icd.long_title LIKE '%acute pancreatitis%')
      OR (d_icd.icd_version = 10 AND d_icd.long_title LIKE '%acute pancreatitis%')
    )
),
diagnosis_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS diagnosis_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
major_complications AS (
  SELECT DISTINCT
    d.hadm_id,
    1 AS has_major_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE
    -- Exclude acute pancreatitis
    NOT (
      (d_icd.icd_version = 9 AND d_icd.long_title LIKE '%acute pancreatitis%')
      OR (d_icd.icd_version = 10 AND d_icd.long_title LIKE '%acute pancreatitis%')
    )
    AND (
      -- Sepsis
      (d_icd.icd_version = 9 AND d_icd.icd_code IN ('995.91', '995.92'))
      OR (d_icd.icd_version = 10 AND d_icd.icd_code IN ('A41.9', 'R65.20', 'R65.21'))
      -- Acute renal failure
      OR (d_icd.icd_version = 9 AND d_icd.icd_code = '584.9')
      OR (d_icd.icd_version = 10 AND d_icd.icd_code = 'N17.9')
      -- Respiratory failure
      OR (d_icd.icd_version = 9 AND d_icd.icd_code = '518.81')
      OR (d_icd.icd_version = 10 AND d_icd.icd_code IN ('J96.90', 'J96.91'))
      -- Shock
      OR (d_icd.icd_version = 9 AND d_icd.icd_code = '785.5')
      OR (d_icd.icd_version = 10 AND d_icd.icd_code = 'R57.9')
      -- Multi-organ failure
      OR (d_icd.icd_version = 10 AND d_icd.icd_code = 'R94.5')
      -- DIC
      OR (d_icd.icd_version = 9 AND d_icd.icd_code = '286.6')
      OR (d_icd.icd_version = 10 AND d_icd.icd_code = 'D65')
      -- Cardiac arrest
      OR (d_icd.icd_version = 9 AND d_icd.icd_code = '427.5')
      OR (d_icd.icd_version = 10 AND d_icd.icd_code = 'I46.9')
      -- Stroke
      OR (d_icd.icd_version = 9 AND d_icd.icd_code IN ('434.91', '436'))
      OR (d_icd.icd_version = 10 AND d_icd.icd_code IN ('I63.9', 'I64'))
      -- Pulmonary embolism
      OR (d_icd.icd_version = 9 AND d_icd.icd_code = '415.19')
      OR (d_icd.icd_version = 10 AND d_icd.icd_code = 'I26.9')
      -- Pancreatic necrosis
      OR (d_icd.icd_version = 10 AND d_icd.icd_code = 'K85.3')
      -- Hemorrhage
      OR (d_icd.icd_version = 9 AND d_icd.icd_code = '578.9')
      OR (d_icd.icd_version = 10 AND d_icd.icd_code = 'K85.8')
    )
),
risk_scores AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.hospital_expire_flag,
    dc.diagnosis_count,
    COALESCE(mc.has_major_complication, 0) AS major_complication_flag,
    dc.diagnosis_count + 5 * COALESCE(mc.has_major_complication, 0) AS risk_score,
    DATETIME_DIFF(pa.dischtime, pa.admittime, DAY) AS los_days
  FROM pancreatitis_admissions pa
  JOIN diagnosis_counts dc ON pa.hadm_id = dc.hadm_id
  LEFT JOIN major_complications mc ON pa.hadm_id = mc.hadm_id
),
quartiles AS (
  SELECT *,
    NTILE(4) OVER (ORDER BY risk_score) AS quartile
  FROM risk_scores
)
SELECT
  CASE 
    WHEN quartile IS NULL THEN 'Overall'
    ELSE 'Q' || CAST(quartile AS STRING)
  END AS quartile,
  AVG(hospital_expire_flag) AS in_hospital_mortality,
  AVG(major_complication_flag) AS major_complication_rate,
  PERCENTILE_CONT(IF(hospital_expire_flag = 0, los_days, NULL), 0.5) AS median_survivor_los
FROM quartiles
GROUP BY GROUPING SETS ((quartile), ())
ORDER BY quartile;