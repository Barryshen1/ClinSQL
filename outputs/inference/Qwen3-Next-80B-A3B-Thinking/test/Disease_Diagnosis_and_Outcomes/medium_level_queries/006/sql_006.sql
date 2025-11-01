WITH sepsis_hadm AS (
  SELECT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_version = 10
    AND (d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%')
  GROUP BY d.hadm_id
  HAVING SUM(CASE WHEN d.icd_code = 'R65.21' THEN 1 ELSE 0 END) = 0
),
cohort AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE a.hadm_id IN (SELECT hadm_id FROM sepsis_hadm)
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
),
cohort_with_los AS (
  SELECT *,
         DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY) AS los_days
  FROM cohort
),
quartiles AS (
  SELECT *,
         NTILE(4) OVER (ORDER BY los_days) AS los_quartile
  FROM cohort_with_los
),
ckd_diabetes AS (
  SELECT d.hadm_id,
         MAX(CASE WHEN d.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS has_ckd,
         MAX(CASE WHEN d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%' OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.hadm_id IN (SELECT hadm_id FROM cohort)
  GROUP BY d.hadm_id
)
SELECT 
  q.los_quartile,
  AVG(q.hospital_expire_flag) AS mortality_rate,
  AVG(cd.has_ckd) AS ckd_prevalence,
  AVG(cd.has_diabetes) AS diabetes_prevalence
FROM quartiles q
JOIN ckd_diabetes cd ON q.hadm_id = cd.hadm_id
GROUP BY q.los_quartile
ORDER BY q.los_quartile;