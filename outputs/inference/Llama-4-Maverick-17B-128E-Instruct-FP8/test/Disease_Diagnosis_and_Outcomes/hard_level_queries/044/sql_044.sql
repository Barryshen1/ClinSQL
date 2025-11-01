WITH patients_cohort AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 59 AND 69
),
cardiac_arrest_patients AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Cardiac arrest%' AND di.hadm_id IN (SELECT hadm_id FROM patients_cohort)
),
comorbidities AS (
  SELECT hadm_id, COUNT(DISTINCT icd_code) as num_comorbidities
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
risk_score AS (
  SELECT pc.subject_id, pc.hadm_id, pc.anchor_age, pc.admittime, pc.dischtime, pc.deathtime,
         COALESCE(c.num_comorbidities, 0) as num_comorbidities,
         pc.anchor_age + COALESCE(c.num_comorbidities, 0) as composite_risk_score
  FROM patients_cohort pc
  LEFT JOIN comorbidities c ON pc.hadm_id = c.hadm_id
  WHERE pc.hadm_id IN (SELECT hadm_id FROM cardiac_arrest_patients)
),
mortality_30day AS (
  SELECT rs.hadm_id,
         CASE WHEN rs.deathtime <= DATETIME_ADD(rs.admittime, INTERVAL 30 DAY) THEN 1 ELSE 0 END as died_30day
  FROM risk_score rs
),
complications AS (
  SELECT rs.hadm_id,
         MAX(CASE WHEN dicd.long_title LIKE '%Cardiovascular%' THEN 1 ELSE 0 END) as cardiovascular_complication,
         MAX(CASE WHEN dicd.long_title LIKE '%Neurologic%' THEN 1 ELSE 0 END) as neurologic_complication
  FROM risk_score rs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON rs.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  GROUP BY rs.hadm_id
),
los AS (
  SELECT rs.hadm_id, DATETIME_DIFF(rs.dischtime, rs.admittime, DAY) as los,
         NTILE(4) OVER (ORDER BY rs.composite_risk_score) as risk_quartile
  FROM risk_score rs
  WHERE rs.dischtime IS NOT NULL
),
quartile_results AS (
  SELECT 
    l.risk_quartile,
    AVG(m.died_30day) as mortality_30day,
    AVG(c.cardiovascular_complication) as cardiovascular_complication_rate,
    AVG(c.neurologic_complication) as neurologic_complication_rate,
    APPROX_QUANTILES(l.los, 2)[OFFSET(1)] AS median_los
  FROM los l
  LEFT JOIN mortality_30day m ON l.hadm_id = m.hadm_id
  LEFT JOIN complications c ON l.hadm_id = c.hadm_id
  GROUP BY l.risk_quartile
),
baseline_mortality AS (
  SELECT AVG(m.died_30day) as baseline_mortality_30day
  FROM patients_cohort pc
  LEFT JOIN mortality_30day m ON pc.hadm_id = m.hadm_id
)
SELECT 
  risk_quartile,
  mortality_30day,
  cardiovascular_complication_rate,
  neurologic_complication_rate,
  median_los,
  (SELECT baseline_mortality_30day FROM baseline_mortality) as baseline_mortality_30day
FROM quartile_results
ORDER BY risk_quartile;