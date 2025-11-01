WITH pneumonia_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id 
    AND d.seq_num = 1
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND a.dischtime IS NOT NULL
    AND (
      (d.icd_version = 'ICD-9' AND (d.icd_code LIKE '48%' OR d.icd_code LIKE '507.0%')) 
      OR (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'J09%' OR d.icd_code LIKE 'J10%' 
          OR d.icd_code LIKE 'J11%' OR d.icd_code LIKE 'J12%' OR d.icd_code LIKE 'J13%' 
          OR d.icd_code LIKE 'J14%' OR d.icd_code LIKE 'J15%' OR d.icd_code LIKE 'J16%' 
          OR d.icd_code LIKE 'J17%' OR d.icd_code LIKE 'J18%')
    )
),
med_complexity AS (
  SELECT 
    pa.*,
    COUNT(DISTINCT COALESCE(TRIM(LOWER(pres.drug)), '')) AS score
  FROM 
    pneumonia_admissions pa
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON CAST(pa.hadm_id AS STRING) = pres.hadm_id
    AND pres.starttime >= pa.admittime 
    AND pres.starttime < TIMESTAMP_ADD(pa.admittime, INTERVAL 7 DAY)
    AND TRIM(LOWER(pres.drug)) IS NOT NULL 
    AND TRIM(LOWER(pres.drug)) != ''
  GROUP BY 
    pa.hadm_id, pa.subject_id, pa.admittime, pa.dischtime, pa.hospital_expire_flag, 
    pa.gender, pa.anchor_age, pa.los_days
),
readmissions AS (
  SELECT 
    *,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime,
    LAG(dischtime) OVER (PARTITION BY subject_id ORDER BY admittime) AS prev_dischtime
  FROM med_complexity
),
cohort AS (
  SELECT 
    *,
    CASE 
      WHEN next_admittime IS NOT NULL 
        AND next_admittime >= dischtime 
        AND next_admittime <= TIMESTAMP_ADD(dischtime, INTERVAL 30 DAY)
      THEN 1 
      ELSE 0 
    END AS readmit_30d_flag
  FROM readmissions
)
SELECT 
  tertile,
  COUNT(*) AS count,
  MIN(score) AS min_score,
  ROUND(AVG(score), 1) AS avg_score,
  MAX(score) AS max_score,
  ROUND(AVG(los_days), 1) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 1) AS in_hosp_mortality_pct,
  ROUND(AVG(readmit_30d_flag) * 100, 1) AS readmit_30d_pct
FROM (
  SELECT 
    *,
    NTILE(3) OVER (ORDER BY score) AS tertile
  FROM cohort
)
GROUP BY tertile
ORDER BY tertile;