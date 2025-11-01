WITH cohort AS (
  SELECT DISTINCT 
    a.hadm_id, 
    a.subject_id, 
    a.admittime, 
    COALESCE(a.deathtime, a.dischtime) AS endtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 
            AND (d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%' 
                 OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' 
                 OR d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%')) 
          OR 
          (d.icd_version = 9 
            AND (d.icd_code LIKE '249%' OR d.icd_code LIKE '250%'))
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%') 
          OR 
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
        )
    )
),
glp1_admins AS (
  SELECT 
    e.subject_id, 
    e.hadm_id, 
    e.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed 
    ON e.subject_id = ed.subject_id 
    AND e.emar_id = ed.emar_id 
    AND e.emar_seq = ed.emar_seq
  WHERE ed.route IN ('Subcutaneous', 'Sub-Q', 'SQ')
    AND (
      e.medication LIKE '%liraglutide%' OR
      e.medication LIKE '%exenatide%' OR
      e.medication LIKE '%dulaglutide%' OR
      e.medication LIKE '%semaglutide%' OR
      e.medication LIKE '%albiglutide%' OR
      e.medication LIKE '%lixisenatide%'
    )
),
glp1_first AS (
  SELECT 
    hadm_id, 
    MIN(charttime) AS first_time
  FROM glp1_admins
  GROUP BY hadm_id
)
SELECT 
  ROUND(
    COUNT(CASE 
      WHEN fs.first_time IS NOT NULL 
        AND fs.first_time >= c.admittime 
        AND fs.first_time < c.admittime + INTERVAL 24 HOUR 
      THEN 1 
    END) * 100.0 / COUNT(c.hadm_id), 2
  ) AS pct_starts_first_24h,
  ROUND(
    COUNT(CASE 
      WHEN fs.first_time IS NOT NULL 
        AND fs.first_time >= c.endtime - INTERVAL 12 HOUR 
        AND fs.first_time < c.endtime 
      THEN 1 
    END) * 100.0 / COUNT(c.hadm_id), 2
  ) AS pct_starts_final_12h,
  COUNT(c.hadm_id) AS total_cohort_size
FROM cohort c
LEFT JOIN glp1_first fs 
  ON c.hadm_id = fs.hadm_id;