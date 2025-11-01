WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
),
dka_admissions AS (
  SELECT DISTINCT
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE dd.icd_version = '10'
    AND dd.icd_code IN ('E10.10', 'E10.11', 'E11.10', 'E11.11', 'E12.10', 'E12.11', 'E13.10', 'E13.11', 'E14.10', 'E14.11')
),
general_admissions AS (
  SELECT 
    e.*
  FROM eligible_admissions e
  WHERE e.hadm_id NOT IN (SELECT hadm_id FROM dka_admissions)
),
aki_admissions AS (
  SELECT DISTINCT
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE dd.icd_version = '10'
    AND dd.icd_code = 'N17.9'
),
ards_admissions AS (
  SELECT DISTINCT
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE dd.icd_version = '10'
    AND dd.icd_code = 'J80'
),
mortality_30d AS (
  SELECT 
    e.hadm_id,
    CASE 
      WHEN e.dod IS NOT NULL AND DATE_DIFF(e.dod, e.admittime, DAY) <= 30 THEN 1 
      ELSE 0 
    END AS died_within_30d
  FROM eligible_admissions e
),
los_survivors AS (
  SELECT 
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los
  FROM eligible_admissions
  WHERE hospital_expire_flag = 0
),
dka_metrics AS (
  SELECT 
    AVG(e.anchor_age) AS mean_risk_score,
    AVG(m.died_within_30d) AS mortality_30d_rate,
    COUNT(DISTINCT CASE WHEN aki.hadm_id IS NOT NULL THEN e.hadm_id END) * 1.0 / COUNT(DISTINCT e.hadm_id) AS aki_rate,
    COUNT(DISTINCT CASE WHEN ards.hadm_id IS NOT NULL THEN e.hadm_id END) * 1.0 / COUNT(DISTINCT e.hadm_id) AS ards_rate,
    AVG(los.los) AS avg_los_survivors
  FROM eligible_admissions e
  INNER JOIN dka_admissions d ON e.hadm_id = d.hadm_id
  LEFT JOIN mortality_30d m ON e.hadm_id = m.hadm_id
  LEFT JOIN aki_admissions aki ON e.hadm_id = aki.hadm_id
  LEFT JOIN ards_admissions ards ON e.hadm_id = ards.hadm_id
  LEFT JOIN los_survivors los ON e.hadm_id = los.hadm_id
),
general_metrics AS (
  SELECT 
    AVG(e.anchor_age) AS mean_risk_score,
    AVG(m.died_within_30d) AS mortality_30d_rate,
    COUNT(DISTINCT CASE WHEN aki.hadm_id IS NOT NULL THEN e.hadm_id END) * 1.0 / COUNT(DISTINCT e.hadm_id) AS aki_rate,
    COUNT(DISTINCT CASE WHEN ards.hadm_id IS NOT NULL THEN e.hadm_id END) * 1.0 / COUNT(DISTINCT e.hadm_id) AS ards_rate,
    AVG(los.los) AS avg_los_survivors
  FROM eligible_admissions e
  INNER JOIN general_admissions g ON e.hadm_id = g.hadm_id
  LEFT JOIN mortality_30d m ON e.hadm_id = m.hadm_id
  LEFT JOIN aki_admissions aki ON e.hadm_id = aki.hadm_id
  LEFT JOIN ards_admissions ards ON e.hadm_id = ards.hadm_id
  LEFT JOIN los_survivors los ON e.hadm_id = los.hadm_id
),
dka_ages AS (
  SELECT e.anchor_age
  FROM eligible_admissions e
  INNER JOIN dka_admissions d ON e.hadm_id = d.hadm_id
),
general_ages AS (
  SELECT e.anchor_age
  FROM eligible_admissions e
  INNER JOIN general_admissions g ON e.hadm_id = g.hadm_id
),
percentile_calc AS (
  SELECT 
    AVG(
      (SELECT COUNT(*) FROM general_ages ga WHERE ga.anchor_age <= da.anchor_age) * 100.0 / (SELECT COUNT(*) FROM general_ages)
    ) AS avg_percentile
  FROM dka_ages da
)
SELECT 
  dka.mean_risk_score,
  dka.mortality_30d_rate,
  dka.aki_rate,
  dka.ards_rate,
  dka.avg_los_survivors,
  gen.mean_risk_score AS general_mean_risk_score,
  gen.mortality_30d_rate AS general_mortality_30d_rate,
  gen.aki_rate AS general_aki_rate,
  gen.ards_rate AS general_ards_rate,
  gen.avg_los_survivors AS general_avg_los_survivors,
  pct.avg_percentile
FROM dka_metrics dka, general_metrics gen, percentile_calc pct;