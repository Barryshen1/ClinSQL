WITH patient_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 76 AND 86
),

pneumonia_admissions AS (
  SELECT DISTINCT pa.*
  FROM patient_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di 
    ON pa.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d 
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (d.icd_version = 9 AND d.icd_code IN ('480','481','482','483','485','486','487.0'))
     OR (d.icd_version = 10 AND d.icd_code LIKE 'J12%' 
         OR d.icd_code LIKE 'J13%' 
         OR d.icd_code LIKE 'J14%' 
         OR d.icd_code LIKE 'J15%' 
         OR d.icd_code LIKE 'J16%' 
         OR d.icd_code LIKE 'J17%' 
         OR d.icd_code LIKE 'J18%')
),

medication_complexity AS (
  SELECT 
    pa.hadm_id,
    COUNT(DISTINCT pr.drug) AS unique_drug_count
  FROM pneumonia_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
    ON pa.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime >= pa.admittime
    AND pr.starttime < DATETIME_ADD(pa.admittime, INTERVAL 7 DAY)
  GROUP BY pa.hadm_id
),

tertiles AS (
  SELECT 
    mc.hadm_id,
    mc.unique_drug_count,
    NTILE(3) OVER (ORDER BY mc.unique_drug_count) AS tertile
  FROM medication_complexity mc
),

readmissions AS (
  SELECT 
    pa1.hadm_id,
    CASE WHEN EXISTS(
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp`.admissions pa2
      WHERE pa2.subject_id = pa1.subject_id
        AND pa2.admittime > pa1.dischtime
        AND DATETIME_DIFF(pa2.admittime, pa1.dischtime, DAY) <= 30
    ) THEN 1 ELSE 0 END AS thirty_day_readmission
  FROM pneumonia_admissions pa1
)

SELECT
  t.tertile,
  COUNT(*) AS admission_count,
  MIN(t.unique_drug_count) AS min_score,
  AVG(t.unique_drug_count) AS avg_score,
  MAX(t.unique_drug_count) AS max_score,
  AVG(DATETIME_DIFF(pa.dischtime, pa.admittime, SECOND) / 3600 / 24.0) AS mean_los_days,
  AVG(pa.hospital_expire_flag) * 100 AS mortality_pct,
  AVG(r.thirty_day_readmission) * 100 AS thirty_day_readmission_pct
FROM tertiles t
JOIN pneumonia_admissions pa ON t.hadm_id = pa.hadm_id
JOIN readmissions r ON pa.hadm_id = r.hadm_id
GROUP BY t.tertile
ORDER BY t.tertile;