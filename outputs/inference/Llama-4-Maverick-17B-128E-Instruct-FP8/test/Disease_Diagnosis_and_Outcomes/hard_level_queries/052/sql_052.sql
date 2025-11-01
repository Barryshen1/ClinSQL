WITH copd_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 75 AND 85
  AND dicd.long_title LIKE '%COPD%'
),
admission_details AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, p.dod,
         DATE_DIFF(COALESCE(a.deathtime, p.dod), a.admittime, DAY) AS survival_days,
         DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE a.hadm_id IN (SELECT hadm_id FROM copd_patients)
),
risk_score_quartiles AS (
  SELECT subject_id, hadm_id,
         NTILE(4) OVER (ORDER BY composite_risk_score) AS risk_quartile
  FROM (
    SELECT cp.subject_id, cp.hadm_id,
           p.anchor_age + 1 AS composite_risk_score
    FROM copd_patients cp
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON cp.subject_id = p.subject_id
  )
),
outcomes AS (
  SELECT risk_quartile,
         COUNT(CASE WHEN survival_days <= 90 THEN 1 END) AS deaths_90d,
         COUNT(*) AS total_patients,
         -- Example complication condition; actual condition may vary
         COUNT(CASE WHEN 1 = 0 THEN 1 END) AS major_complications,
         PERCENTILE_CONT(los, 0.5) AS median_los
  FROM admission_details
  INNER JOIN risk_score_quartiles ON admission_details.hadm_id = risk_score_quartiles.hadm_id
  GROUP BY risk_quartile
)
SELECT risk_quartile,
       deaths_90d / total_patients AS mortality_90d,
       major_complications / total_patients AS complication_rate,
       median_los,
       AVG(deaths_90d / total_patients) OVER () AS broader_mortality_90d
FROM outcomes;