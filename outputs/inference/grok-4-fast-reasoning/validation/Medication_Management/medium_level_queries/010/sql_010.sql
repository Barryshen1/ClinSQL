WITH cohort AS (
  SELECT DISTINCT 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'E11%') OR
          (d.icd_version = 9 AND d.icd_code LIKE '250.%' 
            AND d.icd_code NOT LIKE '250.1%' 
            AND d.icd_code NOT LIKE '250.3%')
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%') OR
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
        )
    )
),
total_cohort AS (
  SELECT COUNT(DISTINCT hadm_id) AS n 
  FROM cohort
),
classes AS (
  SELECT 'Insulin' AS class_name UNION ALL
  SELECT 'Met' UNION ALL
  SELECT 'SU' UNION ALL
  SELECT 'DPP-4' UNION ALL
  SELECT 'SGLT2' UNION ALL
  SELECT 'GLP-1' UNION ALL
  SELECT 'TZD'
),
med_events AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    CASE
      WHEN LOWER(p.medication) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(p.medication) LIKE '%metformin%' THEN 'Met'
      WHEN LOWER(p.medication) LIKE '%glipizide%' 
        OR LOWER(p.medication) LIKE '%glyburide%' 
        OR LOWER(p.medication) LIKE '%glimepiride%' 
        OR LOWER(p.medication) LIKE '%tolbutamide%' 
        OR LOWER(p.medication) LIKE '%tolazamide%' 
        OR LOWER(p.medication) LIKE '%chlorpropamide%' THEN 'SU'
      WHEN LOWER(p.medication) LIKE '%sitagliptin%' 
        OR LOWER(p.medication) LIKE '%saxagliptin%' 
        OR LOWER(p.medication) LIKE '%linagliptin%' 
        OR LOWER(p.medication) LIKE '%alogliptin%' THEN 'DPP-4'
      WHEN LOWER(p.medication) LIKE '%canagliflozin%' 
        OR LOWER(p.medication) LIKE '%dapagliflozin%' 
        OR LOWER(p.medication) LIKE '%empagliflozin%' 
        OR LOWER(p.medication) LIKE '%ertugliflozin%' THEN 'SGLT2'
      WHEN LOWER(p.medication) LIKE '%exenatide%' 
        OR LOWER(p.medication) LIKE '%liraglutide%' 
        OR LOWER(p.medication) LIKE '%dulaglutide%' 
        OR LOWER(p.medication) LIKE '%semaglutide%' 
        OR LOWER(p.medication) LIKE '%albiglutide%' 
        OR LOWER(p.medication) LIKE '%lixisenatide%' THEN 'GLP-1'
      WHEN LOWER(p.medication) LIKE '%pioglitazone%' 
        OR LOWER(p.medication) LIKE '%rosiglitazone%' THEN 'TZD'
      ELSE NULL
    END AS class_name
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy` p
  JOIN cohort c ON p.hadm_id = c.hadm_id
  WHERE p.medication IS NOT NULL
    AND p.starttime IS NOT NULL
    AND CASE
      WHEN LOWER(p.medication) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(p.medication) LIKE '%metformin%' THEN 'Met'
      WHEN LOWER(p.medication) LIKE '%glipizide%' 
        OR LOWER(p.medication) LIKE '%glyburide%' 
        OR LOWER(p.medication) LIKE '%glimepiride%' 
        OR LOWER(p.medication) LIKE '%tolbutamide%' 
        OR LOWER(p.medication) LIKE '%tolazamide%' 
        OR LOWER(p.medication) LIKE '%chlorpropamide%' THEN 'SU'
      WHEN LOWER(p.medication) LIKE '%sitagliptin%' 
        OR LOWER(p.medication) LIKE '%saxagliptin%' 
        OR LOWER(p.medication) LIKE '%linagliptin%' 
        OR LOWER(p.medication) LIKE '%alogliptin%' THEN 'DPP-4'
      WHEN LOWER(p.medication) LIKE '%canagliflozin%' 
        OR LOWER(p.medication) LIKE '%dapagliflozin%' 
        OR LOWER(p.medication) LIKE '%empagliflozin%' 
        OR LOWER(p.medication) LIKE '%ertugliflozin%' THEN 'SGLT2'
      WHEN LOWER(p.medication) LIKE '%exenatide%' 
        OR LOWER(p.medication) LIKE '%liraglutide%' 
        OR LOWER(p.medication) LIKE '%dulaglutide%' 
        OR LOWER(p.medication) LIKE '%semaglutide%' 
        OR LOWER(p.medication) LIKE '%albiglutide%' 
        OR LOWER(p.medication) LIKE '%lixisenatide%' THEN 'GLP-1'
      WHEN LOWER(p.medication) LIKE '%pioglitazone%' 
        OR LOWER(p.medication) LIKE '%rosiglitazone%' THEN 'TZD'
      ELSE NULL
    END IS NOT NULL
),
first12_hadm AS (
  SELECT 
    class_name,
    COUNT(DISTINCT m.hadm_id) AS num_first12
  FROM med_events m
  JOIN cohort c ON m.hadm_id = c.hadm_id
  WHERE m.starttime >= c.admittime 
    AND m.starttime < c.admittime + INTERVAL 12 HOUR
  GROUP BY class_name
),
last48_hadm AS (
  SELECT 
    class_name,
    COUNT(DISTINCT m.hadm_id) AS num_last48
  FROM med_events m
  JOIN cohort c ON m.hadm_id = c.hadm_id
  WHERE m.starttime >= c.dischtime - INTERVAL 48 HOUR 
    AND m.starttime < c.dischtime
  GROUP BY class_name
),
results AS (
  SELECT 
    cl.class_name,
    COALESCE(f.num_first12, 0) AS num_first12,
    COALESCE(l.num_last48, 0) AS num_last48,
    t.n AS total
  FROM classes cl
  LEFT JOIN first12_hadm f ON cl.class_name = f.class_name
  LEFT JOIN last48_hadm l ON cl.class_name = l.class_name
  CROSS JOIN total_cohort t
)
SELECT 
  class_name,
  ROUND((num_first12 * 100.0 / total), 2) AS first12_pct,
  ROUND((num_last48 * 100.0 / total), 2) AS last48_pct,
  ROUND(((num_last48 - num_first12) * 100.0 / total), 2) AS net_change_pp
FROM results
ORDER BY 
  CASE class_name
    WHEN 'Insulin' THEN 1
    WHEN 'Met' THEN 2
    WHEN 'SU' THEN 3
    WHEN 'DPP-4' THEN 4
    WHEN 'SGLT2' THEN 5
    WHEN 'GLP-1' THEN 6
    WHEN 'TZD' THEN 7
  END;