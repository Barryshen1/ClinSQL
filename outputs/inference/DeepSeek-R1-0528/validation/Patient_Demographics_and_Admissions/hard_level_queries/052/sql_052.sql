WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    -- Calculate fractional LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR)/24.0 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN (
    -- Principal diagnosis (seq_num=1) for acute pancreatitis
    SELECT subject_id, hadm_id, icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
    WHERE seq_num = 1
  ) diag 
    ON a.hadm_id = diag.hadm_id AND a.subject_id = diag.subject_id
  WHERE 
    p.gender = 'M'
    AND a.admission_location = 'EMERGENCY ROOM'  -- ED admission
    AND a.insurance = 'Medicare'  -- Medicare patients
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 51 AND 61  -- Age 51-61 at admission
    AND a.hospital_expire_flag = 0  -- Exclude in-hospital deaths
    AND (  -- Acute pancreatitis codes
      (diag.icd_version = 9 AND diag.icd_code = '5770') 
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
    )
),
readm AS (
  SELECT 
    c.*,
    -- Flag readmissions within 30 days of discharge
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2 
      WHERE 
        a2.subject_id = c.subject_id 
        AND a2.hadm_id <> c.hadm_id  -- Different admission
        AND a2.admittime > c.dischtime 
        AND a2.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmitted
  FROM cohort c
),
group_stats AS (
  SELECT 
    readmitted,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,  -- Median LOS
    100.0 * SUM(CASE WHEN los > 9 THEN 1 ELSE 0 END) / COUNT(*) AS pct_los_gt_9  -- % LOS >9 days
  FROM readm
  GROUP BY readmitted
)
-- Final output: Overall readmission rate + group-specific metrics
SELECT 
  'Overall Readmission Rate' AS metric,
  (SELECT COUNTIF(readmitted=1) / COUNT(*) FROM readm) AS value,
  NULL AS median_los,
  NULL AS pct_los_gt_9
UNION ALL
SELECT 
  CONCAT('Readmitted: ', 
         CASE WHEN readmitted=1 THEN 'Yes' ELSE 'No' END) AS metric,
  NULL AS value,
  median_los,
  pct_los_gt_9
FROM group_stats
ORDER BY metric;