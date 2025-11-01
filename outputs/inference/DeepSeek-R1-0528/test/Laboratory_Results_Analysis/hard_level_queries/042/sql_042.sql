WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    a.hospital_expire_flag,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 73 AND 83
    -- ICH diagnosis (ICD-9: 431*, ICD-10: I61*)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE 
        di.subject_id = a.subject_id 
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '431%')
          OR (di.icd_version = 10 AND di.icd_code LIKE 'I61%')
        )
    )
),

labs_abnormal AS (
  SELECT 
    l.subject_id, 
    l.hadm_id, 
    COUNT(DISTINCT l.itemid) AS instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN cohort c
    ON l.subject_id = c.subject_id
    AND l.hadm_id = c.hadm_id
  WHERE 
    l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    AND l.flag IN ('abnormal', 'high', 'low')  -- Abnormal flags
  GROUP BY l.subject_id, l.hadm_id
),

cohort_with_score AS (
  SELECT 
    c.*,
    COALESCE(l.instability_score, 0) AS instability_score,  -- Default 0 if no labs
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days  -- LOS in days
  FROM cohort c
  LEFT JOIN labs_abnormal l
    ON c.subject_id = l.subject_id
    AND c.hadm_id = l.hadm_id
),

quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile  -- Quartile assignment
  FROM cohort_with_score
)

-- Aggregate for overall cohort and quartiles
SELECT 
  'Overall' AS quartile_group,
  COUNT(*) AS count_patients,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM cohort_with_score

UNION ALL

SELECT 
  CAST(quartile AS STRING) AS quartile_group,
  COUNT(*) AS count_patients,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM quartiles
GROUP BY quartile
ORDER BY 
  CASE quartile_group
    WHEN 'Overall' THEN 0
    WHEN '1' THEN 1
    WHEN '2' THEN 2
    WHEN '3' THEN 3
    WHEN '4' THEN 4
  END;