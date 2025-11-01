WITH cohort AS (
  SELECT 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND a.admission_type != 'OBSERVATION'
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'E11%') OR
          (d.icd_version = 9 AND d.icd_code LIKE '250.4%')
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.hadm_id = a.hadm_id
        AND (
          (d2.icd_version = 10 AND d2.icd_code LIKE 'I50%') OR
          (d2.icd_version = 9 AND d2.icd_code LIKE '428%')
        )
    )
),
min_starts AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    MIN(CASE 
      WHEN LOWER(pr.drug) LIKE '%semaglutide%' 
        OR LOWER(pr.drug) LIKE '%liraglutide%' 
        OR LOWER(pr.drug) LIKE '%dulaglutide%' 
        OR LOWER(pr.drug) LIKE '%exenatide%' 
        OR LOWER(pr.drug) LIKE '%lixisenatide%' 
        OR LOWER(pr.drug) LIKE '%albiglutide%' 
      THEN pr.starttime 
      ELSE NULL 
    END) AS min_start
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  GROUP BY c.hadm_id, c.admittime, c.dischtime
)
SELECT 
  total_patients,
  early_count,
  ROUND(100.0 * early_count / total_patients, 2) AS early_percent,
  late_count,
  ROUND(100.0 * late_count / total_patients, 2) AS late_percent,
  ROUND(100.0 * (late_count - early_count) / total_patients, 2) AS net_change_percentage_points
FROM (
  SELECT 
    COUNT(*) AS total_patients,
    SUM(CASE 
      WHEN min_start IS NOT NULL 
        AND min_start >= admittime 
        AND min_start < TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR) 
      THEN 1 
      ELSE 0 
    END) AS early_count,
    SUM(CASE 
      WHEN min_start IS NOT NULL 
        AND min_start >= GREATEST(admittime, TIMESTAMP_SUB(dischtime, INTERVAL 24 HOUR)) 
        AND min_start < dischtime 
      THEN 1 
      ELSE 0 
    END) AS late_count
  FROM min_starts
);