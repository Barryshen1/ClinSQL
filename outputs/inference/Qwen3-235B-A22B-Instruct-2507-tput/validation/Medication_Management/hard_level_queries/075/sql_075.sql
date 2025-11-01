WITH copd_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE LOWER(d_diag.long_title) LIKE '%chronic obstructive pulmonary disease%'
    OR d_diag.icd_code IN ('496', 'J44.0', 'J44.1', 'J44.9')
),
patient_age_gender AS (
  SELECT p.subject_id, p.gender,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 58 AND 68
),
cohort AS (
  SELECT ca.subject_id, ca.hadm_id, ca.admittime, ca.dischtime, ca.hospital_expire_flag
  FROM copd_admissions ca
  INNER JOIN patient_age_gender pag
    ON ca.subject_id = pag.subject_id
  WHERE pag.age_at_admit BETWEEN 58 AND 68
),
medication_complexity AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COUNT(DISTINCT rx.drug) AS complexity_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON c.hadm_id = rx.hadm_id
    AND rx.starttime >= c.admittime
    AND rx.starttime <= DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),
tertiles AS (
  SELECT *,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM medication_complexity
),
readmissions AS (
  SELECT 
    t.*,
    LEAD(t.admittime) OVER (PARTITION BY t.subject_id ORDER BY t.admittime) AS next_admittime
  FROM tertiles t
),
readmit_flag AS (
  SELECT *,
    CASE 
      WHEN next_admittime IS NOT NULL AND DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30 
      THEN 1 ELSE 0 
    END AS thirty_day_readmit
  FROM readmissions
)
SELECT
  tertile,
  COUNT(*) AS n,
  MIN(complexity_score) AS min_complexity,
  MAX(complexity_score) AS max_complexity,
  AVG(complexity_score) AS mean_complexity,
  AVG(DATETIME_DIFF(dischtime, admittime, SECOND) / (60 * 60 * 24)) AS mean_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  AVG(thirty_day_readmit) * 100 AS thirty_day_readmission_pct
FROM readmit_flag
GROUP BY tertile
ORDER BY tertile;