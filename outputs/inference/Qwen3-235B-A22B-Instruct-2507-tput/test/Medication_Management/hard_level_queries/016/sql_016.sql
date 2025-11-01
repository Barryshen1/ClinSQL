WITH hepatic_patients AS (
  SELECT DISTINCT adm.hadm_id, adm.subject_id, adm.admittime, adm.dischtime, 
         adm.hospital_expire_flag, p.anchor_age, 
         DATETIME_ADD(adm.admittime, INTERVAL 7 DAY) AS day7_time
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON adm.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND diag.icd_version = 10
    AND d_diag.icd_code IN ('K704', 'K711', 'K72', 'K720', 'K721', 'K767') -- hepatic failure codes
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
),
medication_complexity AS (
  SELECT hp.hadm_id,
         COUNT(DISTINCT pr.drug) AS unique_medications_7d
  FROM hepatic_patients hp
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON hp.hadm_id = pr.hadm_id
    AND pr.starttime IS NOT NULL
    AND pr.starttime >= hp.admittime
    AND pr.starttime < hp.day7_time
  GROUP BY hp.hadm_id
),
cohort_with_score AS (
  SELECT hp.*, COALESCE(mc.unique_medications_7d, 0) AS med_complexity_score
  FROM hepatic_patients hp
  LEFT JOIN medication_complexity mc ON hp.hadm_id = mc.hadm_id
),
tertiles AS (
  SELECT *,
         NTILE(3) OVER (ORDER BY med_complexity_score) AS tertile
  FROM cohort_with_score
),
readmissions AS (
  SELECT t.*,
         LEAD(t.admittime) OVER (PARTITION BY t.subject_id ORDER BY t.admittime) AS next_admittime
  FROM tertiles t
),
outcomes AS (
  SELECT *,
         DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days,
         CASE WHEN next_admittime IS NOT NULL 
                   AND DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30 
                   AND DATETIME_DIFF(next_admittime, dischtime, DAY) > 0 
              THEN 1 ELSE 0 END AS thirty_day_readmission
  FROM readmissions
)
SELECT 
  tertile,
  AVG(los_days) AS avg_los,
  AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
  AVG(thirty_day_readmission) AS thirty_day_readmission_rate,
  COUNT(*) AS n
FROM outcomes
GROUP BY tertile
ORDER BY tertile;