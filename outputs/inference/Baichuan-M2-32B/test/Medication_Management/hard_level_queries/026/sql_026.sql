WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 76 AND 86
),
all_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    MAX(CASE WHEN d.icd_code IN ('J18.0','J18.9') AND d.icd_version=10 THEN 1 ELSE 0 END) AS has_pneumonia
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN eligible_patients p ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),
pneumonia_admissions AS (
  SELECT subject_id, hadm_id, admittime, dischtime, hospital_expire_flag
  FROM all_admissions
  WHERE has_pneumonia = 1
),
medication_complexity AS (
  SELECT 
    a.hadm_id,
    COUNT(DISTINCT p.drug) AS unique_drugs
  FROM pneumonia_admissions a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    ON a.hadm_id = p.hadm_id
    AND p.starttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 7 DAY)
  GROUP BY a.hadm_id
),
admission_metrics AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE 
      WHEN LEAD(a.admittime) OVER w IS NOT NULL 
        AND TIMESTAMP_DIFF(LEAD(a.admittime) OVER w, a.dischtime, DAY) <= 30 
      THEN 1 
      ELSE 0 
    END AS readmission_flag
  FROM all_admissions a
  WINDOW w AS (PARTITION BY a.subject_id ORDER BY a.admittime)
),
combined_data AS (
  SELECT 
    p.hadm_id,
    p.admittime,
    p.dischtime,
    p.hospital_expire_flag,
    mc.unique_drugs,
    am.los,
    am.readmission_flag
  FROM pneumonia_admissions p
  INNER JOIN medication_complexity mc ON p.hadm_id = mc.hadm_id
  INNER JOIN admission_metrics am ON p.hadm_id = am.hadm_id
),
tertiles AS (
  SELECT 
    *,
    NTILE(3) OVER (ORDER BY unique_drugs) AS tertile
  FROM combined_data
)
SELECT 
  tertile,
  COUNT(*) AS count_admissions,
  MIN(unique_drugs) AS min_unique_drugs,
  AVG(unique_drugs) AS avg_unique_drugs,
  MAX(unique_drugs) AS max_unique_drugs,
  AVG(los) AS mean_los,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percent,
  AVG(readmission_flag) * 100 AS readmission_percent
FROM tertiles
GROUP BY tertile
ORDER BY tertile;