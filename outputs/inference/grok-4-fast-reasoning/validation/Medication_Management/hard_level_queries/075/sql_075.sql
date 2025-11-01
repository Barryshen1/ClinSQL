WITH patients AS (
  SELECT subject_id, anchor_age, anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
),
copd_hadms AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE di.seq_num = 1
    AND (
      (di.icd_version = 10 AND (di.icd_code = 'J440' OR di.icd_code = 'J441'))
      OR
      (di.icd_version = 9 AND di.icd_code = '49121')
    )
),
cohort_adms AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients p ON a.subject_id = p.subject_id
  INNER JOIN copd_hadms ch ON a.hadm_id = ch.hadm_id
  WHERE p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 58 AND 68
),
med_complexity AS (
  SELECT 
    p.hadm_id, 
    COUNT(DISTINCT p.drug) AS complexity_score
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN cohort_adms ca ON p.hadm_id = ca.hadm_id
  WHERE p.starttime >= ca.admittime
    AND p.starttime < TIMESTAMP_ADD(ca.admittime, INTERVAL 3 DAY)
  GROUP BY p.hadm_id
),
cohort_with_score AS (
  SELECT 
    ca.*, 
    COALESCE(mc.complexity_score, 0) AS complexity_score
  FROM cohort_adms ca
  LEFT JOIN med_complexity mc ON ca.hadm_id = mc.hadm_id
),
cohort_with_readmit AS (
  SELECT 
    cws.*,
    CASE 
      WHEN cws.hospital_expire_flag = 1 THEN 0
      ELSE (
        SELECT CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = cws.subject_id
          AND a2.hadm_id != cws.hadm_id
          AND a2.admittime > cws.dischtime
          AND a2.admittime < TIMESTAMP_ADD(cws.dischtime, INTERVAL 30 DAY)
      )
    END AS readmit_30d
  FROM cohort_with_score cws
),
cohort_final AS (
  SELECT *,
    NTILE(3) OVER (ORDER BY complexity_score ASC) AS tertile
  FROM cohort_with_readmit
)
SELECT 
  tertile,
  COUNT(*) AS n,
  MIN(complexity_score) AS min_score,
  MAX(complexity_score) AS max_score,
  ROUND(AVG(complexity_score), 2) AS mean_score,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  ROUND(SUM(readmit_30d) * 100.0 / NULLIF(SUM(1 - hospital_expire_flag), 0), 2) AS readmit_pct
FROM cohort_final
GROUP BY tertile
ORDER BY tertile;