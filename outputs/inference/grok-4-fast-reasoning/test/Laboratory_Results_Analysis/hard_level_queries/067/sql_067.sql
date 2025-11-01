WITH acs_condition AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 9 AND (icd_code LIKE '410.%' OR icd_code = '411.1'))
    OR
    (icd_version = 10 AND (icd_code LIKE 'I21.%' OR icd_code = 'I20.0'))
  )
),
eligible_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
),
cohort AS (
  SELECT 
    ep.*,
    1 AS cohort_type  -- 1 = ACS
  FROM eligible_patients ep
  JOIN acs_condition ac ON ep.hadm_id = ac.hadm_id
  
  UNION ALL
  
  SELECT 
    ep.*,
    0 AS cohort_type  -- 0 = Control
  FROM eligible_patients ep
  WHERE NOT EXISTS (
    SELECT 1 
    FROM acs_condition ac 
    WHERE ac.hadm_id = ep.hadm_id
  )
),
scores AS (
  SELECT 
    ep.hadm_id,
    COALESCE(
      COUNT(DISTINCT CASE 
        WHEN l.flag IS NOT NULL 
          AND l.flag != '' 
          AND li.category IS NOT NULL 
        THEN li.category 
      END), 
      0
    ) AS instability_score
  FROM eligible_patients ep
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON ep.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON l.hadm_id = a.hadm_id 
    AND l.charttime >= a.admittime 
    AND l.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li 
    ON l.itemid = li.itemid
  GROUP BY ep.hadm_id
),
cohort_with_scores AS (
  SELECT 
    c.*,
    COALESCE(s.instability_score, 0) AS instability_score
  FROM cohort c
  LEFT JOIN scores s ON c.hadm_id = s.hadm_id
),
acs_with_quartile AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile
  FROM cohort_with_scores
  WHERE cohort_type = 1
),
acs_quartiles AS (
  SELECT 
    quartile,
    COUNT(*) AS n_patients,
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
    ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0), 2) AS avg_los_days
  FROM acs_with_quartile
  GROUP BY quartile
),
controls_summary AS (
  SELECT 
    COUNT(*) AS n_patients,
    ROUND(AVG(c.hospital_expire_flag) * 100, 2) AS mortality_pct,
    ROUND(AVG(TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) / 24.0), 2) AS avg_los_days,
    ROUND(AVG(c.instability_score), 2) AS avg_score,
    ROUND(AVG(CASE WHEN c.instability_score > 0 THEN 1.0 ELSE 0 END) * 100, 2) AS pct_with_critical_labs
  FROM cohort_with_scores c
  WHERE c.cohort_type = 0
)
SELECT 
  'ACS Quartile' AS report_section,
  quartile,
  n_patients,
  mortality_pct,
  avg_los_days,
  NULL AS avg_score,
  NULL AS pct_with_critical_labs
FROM acs_quartiles

UNION ALL

SELECT 
  'Controls Summary' AS report_section,
  NULL AS quartile,
  n_patients,
  mortality_pct,
  avg_los_days,
  avg_score,
  pct_with_critical_labs
FROM controls_summary

ORDER BY report_section, quartile NULLS LAST;