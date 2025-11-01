WITH hf_patients AS (
  SELECT DISTINCT h.subject_id, h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON h.icd_code = d.icd_code AND h.icd_version = d.icd_version
  WHERE d.long_title LIKE '%Heart failure%' AND h.icd_version = 10
),
patient_info AS (
  SELECT p.subject_id, p.gender, a.hadm_id, a.admittime, a.dischtime, a.deathtime, 
         TIMESTAMP_DIFF(a.deathtime, a.admittime, HOUR) AS survival_hours,
         a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN hf_patients ON a.hadm_id = hf_patients.hadm_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 59 AND 69
),
aki_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code LIKE 'N17%' AND icd_version = 10
),
ards_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code LIKE 'J80%' AND icd_version = 10
),
mortality_risk_scores AS (
  SELECT hadm_id, 
         -- Placeholder for actual risk score calculation
         RAND() AS risk_score
  FROM patient_info
)

SELECT 
  COUNTIF(hospital_expire_flag = 1) / COUNT(*) AS in_hospital_mortality_rate,
  COUNTIF(pi.hadm_id IN (SELECT hadm_id FROM aki_patients)) / COUNT(*) AS aki_rate,
  COUNTIF(pi.hadm_id IN (SELECT hadm_id FROM ards_patients)) / COUNT(*) AS ards_rate,
  APPROX_QUANTILES(survival_hours, 100)[OFFSET(50)] AS median_survival_hours,
  MIN(mrs.risk_score) AS min_risk_score,
  APPROX_QUANTILES(mrs.risk_score, 100)[OFFSET(25)] AS p25_risk_score,
  APPROX_QUANTILES(mrs.risk_score, 100)[OFFSET(50)] AS median_risk_score,
  APPROX_QUANTILES(mrs.risk_score, 100)[OFFSET(75)] AS p75_risk_score,
  APPROX_QUANTILES(mrs.risk_score, 100)[OFFSET(90)] AS p90_risk_score,
  MAX(mrs.risk_score) AS max_risk_score
FROM patient_info pi
LEFT JOIN mortality_risk_scores mrs ON pi.hadm_id = mrs.hadm_id;