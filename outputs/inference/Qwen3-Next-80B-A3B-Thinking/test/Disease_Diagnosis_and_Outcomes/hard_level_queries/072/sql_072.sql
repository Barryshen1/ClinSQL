WITH acs_cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 67 AND 77
    AND d.icd_code IN (
      'I20.0', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4',
      'I22.0', 'I22.1', 'I22.2', 'I22.3', 'I22.4', 'I22.5', 'I22.6', 'I22.7', 'I22.8', 'I22.9'
    )
),

control_cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 67 AND 77
),

acs_risk_score AS (
  SELECT AVG(d.drg_mortality) AS mean_risk_score
  FROM acs_cohort acs
  JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` d ON acs.hadm_id = d.hadm_id
),

acs_mortality AS (
  SELECT 
    SUM(CASE WHEN p.dod IS NOT NULL AND p.dod <= DATE_ADD(a.dischtime, INTERVAL 30 DAY) THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS thirty_day_mortality
  FROM acs_cohort acs
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON acs.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON acs.hadm_id = a.hadm_id
),

acs_survivor_los AS (
  SELECT AVG(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS survivor_mean_los
  FROM acs_cohort acs
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON acs.hadm_id = a.hadm_id
  WHERE a.hospital_expire_flag = 0
),

control_cardiac AS (
  SELECT 
    SUM(CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = c.hadm_id 
        AND (d.icd_code LIKE 'I50%' OR d.icd_code LIKE 'I49%' OR d.icd_code LIKE 'I44%' OR d.icd_code LIKE 'I45%' OR d.icd_code LIKE 'I46%' OR d.icd_code LIKE 'I47%' OR d.icd_code LIKE 'I48%' OR d.icd_code LIKE 'I51.4%' OR d.icd_code LIKE 'I97.1%')
    ) THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS cardiac_complication_rate
  FROM control_cohort c
),

control_neurologic AS (
  SELECT 
    SUM(CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = c.hadm_id 
        AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%' OR d.icd_code LIKE 'I63%' OR d.icd_code LIKE 'I64%' OR d.icd_code LIKE 'I67%' OR d.icd_code LIKE 'I69%' OR d.icd_code LIKE 'G40%' OR d.icd_code LIKE 'G41%' OR d.icd_code LIKE 'G42%' OR d.icd_code LIKE 'G43%' OR d.icd_code LIKE 'G44%' OR d.icd_code LIKE 'G45%' OR d.icd_code LIKE 'G46%' OR d.icd_code LIKE 'G47%')
    ) THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS neurologic_complication_rate
  FROM control_cohort c
),

control_survivor_los AS (
  SELECT AVG(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS survivor_mean_los
  FROM control_cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
  WHERE a.hospital_expire_flag = 0
),

control_los_values AS (
  SELECT DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM control_cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
  WHERE a.hospital_expire_flag = 0
),

percentile_calc AS (
  SELECT 
    (COUNTIF(los <= (SELECT survivor_mean_los FROM acs_survivor_los)) * 100.0) / COUNT(*) AS matched_percentile
  FROM control_los_values
)

SELECT 
  acs_risk_score.mean_risk_score,
  acs_mortality.thirty_day_mortality,
  control_cardiac.cardiac_complication_rate,
  control_neurologic.neurologic_complication_rate,
  control_survivor_los.survivor_mean_los AS control_survivor_los,
  acs_survivor_los.survivor_mean_los AS acs_survivor_los,
  percentile_calc.matched_percentile
FROM acs_risk_score, acs_mortality, control_cardiac, control_neurologic, control_survivor_los, acs_survivor_los, percentile_calc;