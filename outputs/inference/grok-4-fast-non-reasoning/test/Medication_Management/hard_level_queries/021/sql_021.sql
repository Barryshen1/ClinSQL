WITH cohort AS (
  -- Base cohort: males aged 41-51
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND a.admission_type != 'NEWBORN'
    AND a.admission_location != 'NEWBORN'
    AND a.admission_type != 'OBSERVATION'
),

neutropenia AS (
  -- Admissions with neutropenia diagnosis (ICD-10 D70*, ICD-9 288.0)
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE ((di.icd_version = '10' AND di.icd_code LIKE 'D70%')
     OR (di.icd_version = '9' AND di.icd_code = '288.0'))
    AND LOWER(d.long_title) LIKE '%neutropenia%'
),

fever AS (
  -- Admissions with fever (temp >= 100.4 F) in first 7 days, using chartevents
  SELECT DISTINCT ce.subject_id, ce.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort c
    ON ce.subject_id = c.subject_id AND ce.hadm_id = c.hadm_id
  WHERE ce.itemid = 6768  -- Temperature Fahrenheit (vitals)
    AND ce.valuenum >= 100.4
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= c.admittime
    AND ce.charttime < c.admittime + INTERVAL 7 DAY
    AND ce.charttime < c.dischtime
),

med_count AS (
  -- Unique medications in first 48 hours
  SELECT 
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT CASE 
      WHEN pr.drug IS NOT NULL AND LENGTH(TRIM(pr.drug)) > 0 
      THEN pr.drug 
      ELSE NULL 
    END) AS unique_meds
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id 
    AND c.hadm_id = pr.hadm_id
    AND pr.starttime >= c.admittime
    AND pr.starttime < c.admittime + INTERVAL 2 DAY
    AND pr.starttime IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id
),

readmits AS (
  -- Flag 30-day readmissions (exclude observation and newborn)
  SELECT 
    c.subject_id,
    c.hadm_id,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p2
        ON a2.subject_id = p2.subject_id
      WHERE a2.subject_id = c.subject_id
        AND a2.hadm_id != c.hadm_id
        AND a2.admittime > c.dischtime
        AND a2.admittime <= c.dischtime + INTERVAL 30 DAY
        AND a2.admission_type != 'OBSERVATION'
        AND a2.admission_type != 'NEWBORN'
        AND a2.admission_location != 'NEWBORN'
        AND p2.anchor_age BETWEEN 41 AND 51  -- Same age group
    ) THEN 1 ELSE 0 END AS has_readmit
  FROM cohort c
)

-- Final aggregation
SELECT 
  tertile,
  COUNT(*) AS n,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  ROUND(AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) * 100, 2) AS mortality_pct,
  ROUND(AVG(CASE WHEN r.has_readmit = 1 THEN 1.0 ELSE 0 END) * 100, 2) AS readmit_30d_pct
FROM (
  SELECT 
    c.*,
    COALESCE(m.unique_meds, 0) AS unique_meds,
    r.has_readmit,
    NTILE(3) OVER (ORDER BY COALESCE(m.unique_meds, 0)) AS tertile
  FROM cohort c
  INNER JOIN neutropenia n ON c.subject_id = n.subject_id AND c.hadm_id = n.hadm_id
  INNER JOIN fever f ON c.subject_id = f.subject_id AND c.hadm_id = f.hadm_id
  LEFT JOIN med_count m ON c.subject_id = m.subject_id AND c.hadm_id = m.hadm_id
  LEFT JOIN readmits r ON c.subject_id = r.subject_id AND c.hadm_id = r.hadm_id
)
GROUP BY tertile
ORDER BY tertile;