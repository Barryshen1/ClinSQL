WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 35 AND 45
),
pancreatitis_admissions AS (
  SELECT 
    c.*
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
  WHERE 
    d.icd_version = 10 
    AND d.icd_code = 'K31.8'
  GROUP BY c.hadm_id, c.subject_id, c.admittime, c.dischtime, c.hospital_expire_flag, c.age_at_admission
),
admission_metrics AS (
  SELECT 
    p.hadm_id,
    p.subject_id,
    p.admittime,
    p.dischtime,
    p.hospital_expire_flag,
    p.age_at_admission,
    COUNT(DISTINCT d_all.icd_code) AS diagnosis_count,
    MAX(CASE WHEN d_comp.icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS flag_akidney_injury,
    MAX(CASE WHEN d_comp.icd_code IN ('A40','A41') THEN 1 ELSE 0 END) AS flag_sepsis,
    MAX(CASE WHEN d_comp.icd_code = 'J96.9' THEN 1 ELSE 0 END) AS flag_resp_fail,
    MAX(CASE WHEN d_comp.icd_code = 'I46.9' THEN 1 ELSE 0 END) AS flag_cardiac_arrest,
    MAX(CASE WHEN d_comp.icd_code = 'K72.9' THEN 1 ELSE 0 END) AS flag_liver_fail,
    MAX(CASE WHEN d_comp.icd_code = 'D68.8' THEN 1 ELSE 0 END) AS flag_dic,
    MAX(CASE WHEN d_comp.icd_code = 'N17.9' THEN 1 ELSE 0 END) AS flag_renal_fail,
    MAX(CASE WHEN d_comp.icd_code = 'R68.8' THEN 1 ELSE 0 END) AS flag_multi_org_fail,
    MAX(CASE WHEN d_comp.icd_code = 'I50.9' THEN 1 ELSE 0 END) AS flag_heart_fail,
    MAX(CASE WHEN d_comp.icd_code = 'J80' THEN 1 ELSE 0 END) AS flag_arcs
  FROM pancreatitis_admissions p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_all 
    ON p.subject_id = d_all.subject_id AND p.hadm_id = d_all.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_comp 
    ON p.subject_id = d_comp.subject_id AND p.hadm_id = d_comp.hadm_id AND d_comp.icd_version = 10
  GROUP BY p.hadm_id, p.subject_id, p.admittime, p.dischtime, p.hospital_expire_flag, p.age_at_admission
),
risk_scores AS (
  SELECT 
    *,
    flag_akidney_injury + flag_sepsis + flag_resp_fail + flag_cardiac_arrest + flag_liver_fail + flag_dic + flag_renal_fail + flag_multi_org_fail + flag_heart_fail + flag_arcs AS total_flags,
    diagnosis_count + 5 * total_flags AS risk_score
  FROM admission_metrics
),
quartiled AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY risk_score) AS quartile
  FROM risk_scores
),
quartile_metrics AS (
  SELECT 
    quartile,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality,
    AVG(CAST(total_flags > 0 AS FLOAT64)) AS major_complication_rate,
    APPROX_QUANTILES(
      IF(hospital_expire_flag = 0, TIMESTAMP_DIFF(dischtime, admittime, DAY), NULL), 
      100
    )[OFFSET(50)] AS median_survivor_los
  FROM quartiled
  GROUP BY ROLLUP(quartile)
)
SELECT 
  COALESCE(CAST(quartile AS STRING), 'Overall') AS quartile,
  in_hospital_mortality,
  major_complication_rate,
  median_survivor_los
FROM quartile_metrics
ORDER BY quartile;