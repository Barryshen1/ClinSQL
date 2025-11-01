WITH cohort_hadm AS (
  SELECT DISTINCT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND (
      (d.icd_version = 9 AND d.icd_code = '4275') 
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I46%')
    )
),
med_scores AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    c.admittime, 
    c.dischtime, 
    c.hospital_expire_flag,
    COUNT(DISTINCT pr.drug) AS med_score
  FROM cohort_hadm c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON pr.subject_id = c.subject_id 
    AND pr.hadm_id = c.hadm_id
    AND pr.starttime >= c.admittime 
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 7 DAY)
    AND pr.drug IS NOT NULL 
    AND TRIM(pr.drug) != ''
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),
base AS (
  SELECT 
    ms.*,
    DATE_DIFF(ms.dischtime, ms.admittime, DAY) AS los,
    CAST((ms.hospital_expire_flag = 1) AS INT64) AS died,
    CASE 
      WHEN ms.hospital_expire_flag = 1 OR ms.dischtime IS NULL THEN 0
      ELSE CAST((
        EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
          WHERE a2.subject_id = ms.subject_id
            AND a2.hadm_id != ms.hadm_id
            AND a2.admittime > ms.dischtime
            AND a2.admittime <= TIMESTAMP_ADD(ms.dischtime, INTERVAL 30 DAY)
        )
      ) AS INT64)
    END AS has_readmit,
    NTILE(5) OVER (ORDER BY ms.med_score ASC) AS quintile
  FROM med_scores ms
)
SELECT 
  quintile,
  COUNT(*) AS patient_count,
  ROUND(AVG(med_score), 2) AS avg_score,
  MIN(med_score) AS min_score,
  MAX(med_score) AS max_score,
  ROUND(AVG(los), 2) AS avg_los,
  ROUND((SUM(died) * 100.0 / COUNT(*)), 2) AS mortality_pct,
  ROUND((SUM(has_readmit) * 100.0 / NULLIF(COUNT(*) - SUM(died), 0)), 2) AS readmit_30d_pct
FROM base
GROUP BY quintile
ORDER BY quintile;