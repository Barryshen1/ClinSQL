WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 73 AND 83
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code = '431') 
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I61%')
        )
    )
),
scores AS (
  SELECT 
    le.hadm_id,
    COUNT(DISTINCT li.category) AS instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li 
    ON le.itemid = CAST(li.itemid AS INT64)
  JOIN cohort c 
    ON le.hadm_id = c.hadm_id
  WHERE le.flag = 'abnormal'
    AND li.category IS NOT NULL
    AND le.charttime >= c.admittime
    AND le.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 2 DAY)
  GROUP BY le.hadm_id
),
with_scores AS (
  SELECT 
    c.*,
    COALESCE(s.instability_score, 0) AS instability_score
  FROM cohort c
  LEFT JOIN scores s 
    ON c.hadm_id = s.hadm_id
),
quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY instability_score ASC) AS quartile
  FROM with_scores
),
cohort_stats AS (
  SELECT 
    CAST(quartile AS STRING) AS group_name,
    COUNT(*) AS n,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
    SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate
  FROM quartiles
  GROUP BY quartile
  ORDER BY quartile
),
all_inpatients AS (
  SELECT 
    'All' AS group_name,
    COUNT(*) AS n,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
    SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
)
SELECT * FROM cohort_stats
UNION ALL
SELECT * FROM all_inpatients
ORDER BY 
  CASE 
    WHEN group_name = 'All' THEN 5 
    ELSE CAST(group_name AS INT64) 
  END;