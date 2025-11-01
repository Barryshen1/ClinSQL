WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    COUNT(DISTINCT pres.drug) AS med_score
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pres 
    ON a.hadm_id = pres.hadm_id 
    AND pres.starttime >= a.admittime 
    AND pres.starttime < TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY)
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'I26.%')
      OR (d.icd_version = 9 AND d.icd_code = '4151')
    )
  GROUP BY 
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),
tertiles AS (
  SELECT 
    *,
    NTILE(3) OVER (ORDER BY med_score) AS tertile
  FROM cohort
),
readmit_flags AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN FALSE
      ELSE EXISTS(
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = tertiles.subject_id
          AND a2.hadm_id <> tertiles.hadm_id
          AND a2.admittime > tertiles.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(tertiles.dischtime, INTERVAL 30 DAY)
      )
    END AS has_readmission
  FROM tertiles
)
SELECT 
  tertile,
  COUNT(*) AS admissions,
  MIN(med_score) AS min_med_score,
  MAX(med_score) AS max_med_score,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
  (SUM(CAST(hospital_expire_flag AS INT64)) * 100.0 / COUNT(*)) AS mortality_pct,
  (SUM(CAST(has_readmission AS INT64)) * 100.0 / SUM(CASE WHEN hospital_expire_flag = 0 THEN 1 ELSE 0 END)) AS readmission_30d_pct
FROM readmit_flags
GROUP BY tertile
ORDER BY tertile;