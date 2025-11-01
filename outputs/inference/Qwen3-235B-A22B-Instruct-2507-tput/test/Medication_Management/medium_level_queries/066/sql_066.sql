WITH eligible_diagnoses AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_version = 10
    AND (d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'I50%')
  GROUP BY di.hadm_id
  HAVING 
    SUM(CASE WHEN d.icd_code LIKE 'E11%' THEN 1 ELSE 0 END) > 0
    AND SUM(CASE WHEN d.icd_code LIKE 'I50%' THEN 1 ELSE 0 END) > 0
),
eligible_admissions AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN eligible_diagnoses ed
    ON a.hadm_id = ed.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND a.dischtime IS NOT NULL
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),
glp1_drugs AS (
  SELECT LOWER(drug) AS drug
  FROM UNNEST([
    'exenatide', 'liraglutide', 'dulaglutide', 
    'semaglutide', 'lixisenatide'
  ]) AS drug
),
drug_exposure AS (
  SELECT 
    ea.hadm_id,
    MAX(CASE 
      WHEN p.starttime >= ea.admittime 
       AND p.starttime <= DATETIME_ADD(ea.admittime, INTERVAL 72 HOUR)
      THEN 1 ELSE 0 END) AS started_early,
    MAX(CASE 
      WHEN p.starttime >= DATETIME_SUB(ea.dischtime, INTERVAL 12 HOUR)
       AND p.starttime <= ea.dischtime
      THEN 1 ELSE 0 END) AS started_late
  FROM eligible_admissions ea
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON ea.hadm_id = p.hadm_id
    AND p.starttime IS NOT NULL
  INNER JOIN glp1_drugs g
    ON LOWER(p.drug) = g.drug
  GROUP BY ea.hadm_id
),
summary_stats AS (
  SELECT
    AVG(started_early) * 100 AS pct_started_early,
    AVG(started_late) * 100 AS pct_started_late
  FROM drug_exposure
)
SELECT
  ROUND(pct_started_early, 2) AS pct_started_early,
  ROUND(pct_started_late, 2) AS pct_started_late,
  ROUND(pct_started_early - pct_started_late, 2) AS absolute_difference
FROM summary_stats;