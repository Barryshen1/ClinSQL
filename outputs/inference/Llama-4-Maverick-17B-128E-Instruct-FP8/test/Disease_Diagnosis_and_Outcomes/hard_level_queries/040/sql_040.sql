WITH 
ich_admissions AS (
  SELECT DISTINCT a.hadm_id, a.admittime, a.dischtime, a.deathtime, p.subject_id, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND dicd.long_title LIKE '%Intracranial hemorrhage%'
    AND a.admittime IS NOT NULL
),
risk_scores AS (
  SELECT hadm_id, 
         (anchor_age + (CASE WHEN gender = 'F' THEN 1 ELSE 0 END)) AS composite_risk_score
  FROM ich_admissions
),
quintiles AS (
  SELECT hadm_id, composite_risk_score,
         NTILE(5) OVER (ORDER BY composite_risk_score) AS quintile
  FROM risk_scores
),
admission_outcomes AS (
  SELECT q.quintile,
         COUNT(*) AS n,
         SUM(CASE WHEN ia.deathtime <= ia.admittime + INTERVAL 30 DAY THEN 1 ELSE 0 END) / COUNT(*) * 100 AS mortality_30day_percent,
         APPROX_QUANTILES(DATE_DIFF(ia.dischtime, ia.admittime, DAY), 1000)[OFFSET(500)] AS median_los
  FROM quintiles q
  INNER JOIN ich_admissions ia ON q.hadm_id = ia.hadm_id
  GROUP BY q.quintile
)
SELECT quintile, n, mortality_30day_percent, median_los
FROM admission_outcomes
ORDER BY quintile;