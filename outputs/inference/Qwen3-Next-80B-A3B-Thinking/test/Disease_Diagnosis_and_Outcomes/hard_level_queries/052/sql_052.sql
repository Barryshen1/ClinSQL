WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND d.long_title LIKE '%exacerbation%'
),

cci_mapping AS (
  SELECT 'I21' AS icd_code, 1 AS points UNION ALL
  SELECT 'I50', 1 UNION ALL
  SELECT 'I70', 1 UNION ALL
  SELECT 'I60', 1 UNION ALL
  SELECT 'F01', 1 UNION ALL
  SELECT 'J44', 1 UNION ALL
  SELECT 'M05', 1 UNION ALL
  SELECT 'K25', 1 UNION ALL
  SELECT 'K70', 1 UNION ALL
  SELECT 'E10', 1 UNION ALL
  SELECT 'E11', 1 UNION ALL
  SELECT 'E13', 1 UNION ALL
  SELECT 'E10.2', 2 UNION ALL
  SELECT 'E11.2', 2 UNION ALL
  SELECT 'E13.2', 2 UNION ALL
  SELECT 'G04', 2 UNION ALL
  SELECT 'N18', 2 UNION ALL
  SELECT 'C%', 2 UNION ALL
  SELECT 'K71', 3 UNION ALL
  SELECT 'C77', 6 UNION ALL
  SELECT 'B20', 6
),

cci_scores AS (
  SELECT 
    di.hadm_id,
    SUM(cm.points) AS cci_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN cci_mapping cm
    ON di.icd_code LIKE cm.icd_code
  GROUP BY di.hadm_id
),

complications AS (
  SELECT 
    di.hadm_id,
    MAX(CASE WHEN d.long_title LIKE '%sepsis%' THEN 1 ELSE 0 END) AS has_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY di.hadm_id
),

cohort_with_metrics AS (
  SELECT 
    c.*,
    COALESCE(cci.cci_score, 0) AS cci_score,
    comp.has_complication,
    CASE 
      WHEN c.dod IS NOT NULL AND c.dod <= DATE_ADD(c.admittime, INTERVAL 90 DAY) THEN 1 
      ELSE 0 
    END AS died_90,
    CASE 
      WHEN c.dod IS NULL OR c.dod > DATE_ADD(c.admittime, INTERVAL 90 DAY) 
      THEN DATE_DIFF(c.dischtime, c.admittime, DAY) 
    END AS los_survivor
  FROM cohort c
  LEFT JOIN cci_scores cci ON c.hadm_id = cci.hadm_id
  LEFT JOIN complications comp ON c.hadm_id = comp.hadm_id
)

SELECT 
  quartile,
  AVG(died_90) AS ninety_day_mortality,
  AVG(has_complication) AS major_complication_rate,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los_survivor) AS median_survivor_los,
  (SELECT AVG(died_90) FROM cohort_with_metrics) AS overall_ninety_day_mortality
FROM (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY cci_score) AS quartile
  FROM cohort_with_metrics
) sub
GROUP BY quartile
ORDER BY quartile;