WITH cohort AS (
  -- Base cohort: males 68-78 with diabetes + acute HF
  SELECT DISTINCT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 24  -- Ensure at least 24h LOS
    AND d.icd_version IN ('9', '10')  -- Focus on common ICD versions
    AND (
      -- Diabetes ICD-9/10
      (LOWER(d.icd_code) LIKE 'e1[0-4]%' OR LOWER(d.icd_code) LIKE '250%') OR
      -- Acute HF ICD-9/10
      (LOWER(d.icd_code) LIKE 'i50%' OR LOWER(d.icd_code) LIKE '428%')
    )
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, p.gender, p.anchor_age, los_hours
  HAVING COUNT(DISTINCT 
    CASE 
      WHEN LOWER(d.icd_code) LIKE 'e1[0-4]%' OR LOWER(d.icd_code) LIKE '250%' THEN 1 
      ELSE NULL 
    END) > 0  -- Has diabetes
    AND COUNT(DISTINCT 
      CASE 
        WHEN LOWER(d.icd_code) LIKE 'i50%' OR LOWER(d.icd_code) LIKE '428%' THEN 1 
        ELSE NULL 
      END) > 0  -- Has acute HF
),

insulin_initiations AS (
  -- Insulin initiations (starts during admission)
  SELECT 
    c.hadm_id,
    MIN(pr.starttime) AS first_starttime
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE LOWER(pr.drug) LIKE '%insulin%'
    AND pr.starttime >= c.admittime  -- During admission only
  GROUP BY c.hadm_id, c.admittime
  HAVING MIN(pr.starttime) IS NOT NULL  -- At least one start
),

oral_initiations AS (
  -- Oral agent initiations (common orals during admission)
  SELECT 
    c.hadm_id,
    MIN(pr.starttime) AS first_starttime
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE LOWER(pr.drug) IN ('metformin', 'glipizide', 'glyburide', 'glimepiride', 'pioglitazone', 'sitagliptin', 'repaglinide')
    AND pr.starttime >= c.admittime  -- During admission only
  GROUP BY c.hadm_id, c.admittime
  HAVING MIN(pr.starttime) IS NOT NULL  -- At least one start
),

window_inits AS (
  -- First 24h: initiations in [admittime, admittime + 24h)
  SELECT 
    c.hadm_id,
    'first_24h' AS window,
    CASE WHEN ii.hadm_id IS NOT NULL 
         AND ii.first_starttime >= c.admittime 
         AND ii.first_starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR) 
         THEN 1 ELSE 0 END AS has_insulin_init,
    CASE WHEN oi.hadm_id IS NOT NULL 
         AND oi.first_starttime >= c.admittime 
         AND oi.first_starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR) 
         THEN 1 ELSE 0 END AS has_oral_init
  FROM cohort c
  LEFT JOIN insulin_initiations ii ON c.hadm_id = ii.hadm_id
  LEFT JOIN oral_initiations oi ON c.hadm_id = oi.hadm_id

  UNION ALL
  -- Final 24h: initiations in [dischtime - 24h, dischtime)
  SELECT 
    c.hadm_id,
    'final_24h' AS window,
    CASE WHEN ii.hadm_id IS NOT NULL 
         AND ii.first_starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) 
         AND ii.first_starttime < c.dischtime 
         THEN 1 ELSE 0 END AS has_insulin_init,
    CASE WHEN oi.hadm_id IS NOT NULL 
         AND oi.first_starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) 
         AND oi.first_starttime < c.dischtime 
         THEN 1 ELSE 0 END AS has_oral_init
  FROM cohort c
  LEFT JOIN insulin_initiations ii ON c.hadm_id = ii.hadm_id
  LEFT JOIN oral_initiations oi ON c.hadm_id = oi.hadm_id
)

-- Final aggregation: rates and differences
SELECT 
  window,
  ROUND(AVG(has_insulin_init) * 100, 2) AS insulin_initiation_rate_pct,
  ROUND(AVG(has_oral_init) * 100, 2) AS oral_initiation_rate_pct,
  ROUND(AVG(has_insulin_init) * 100 - AVG(has_oral_init) * 100, 2) AS absolute_diff_pct_points
FROM window_inits
GROUP BY window
ORDER BY 
  CASE window 
    WHEN 'first_24h' THEN 1 
    ELSE 2 
  END;