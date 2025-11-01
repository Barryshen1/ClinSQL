WITH 
admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    a.admission_location,
    a.admission_type
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    a.admission_type = 'Emergency'
    AND p.anchor_age BETWEEN 65 AND 75
    AND p.gender = 'M'
    AND a.admission_location = 'ED'
),
los AS (
  SELECT 
    hadm_id,
    DATE_DIFF(dischtime, admittime) AS los_days,
    CASE 
      WHEN EXISTS (
        SELECT 
          1 
        FROM 
          `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE 
          a2.hadm_id > admissions.hadm_id
          AND a2.subject_id = admissions.subject_id
      ) THEN 'readmitted'
      ELSE 'not_readmitted'
    END AS readmission_status
  FROM 
    admissions
)
SELECT 
  COUNT(DISTINCT CASE WHEN readmission_status = 'readmitted' THEN hadm_id END) AS readmitted_count,
  COUNT(DISTINCT CASE WHEN readmission_status = 'not_readmitted' THEN hadm_id END) AS not_readmitted_count,
  COUNT(DISTINCT CASE WHEN readmission_status = 'readmitted' THEN hadm_id END) * 1.0 / 
  (COUNT(DISTINCT CASE WHEN readmission_status = 'readmitted' THEN hadm_id END) + 
   COUNT(DISTINCT CASE WHEN readmission_status = 'not_readmitted' THEN hadm_id END)) AS readmission_rate,
  PERCENTILE_CONT(0.5)(los_days) OVER (PARTITION BY readmission_status) AS median_los_readmitted,
  SUM(CASE WHEN readmission_status = 'readmitted' AND los_days > 9 THEN 1 ELSE 0 END) * 1.0 / 
  COUNT(DISTINCT CASE WHEN readmission_status = 'readmitted' THEN hadm_id END) * 100 AS percent_los_gt_9_days_readmitted,
  SUM(CASE WHEN readmission_status = 'not_readmitted' AND los_days > 9 THEN 1 ELSE 0 END) * 1.0 / 
  COUNT(DISTINCT CASE WHEN readmission_status = 'not_readmitted' THEN hadm_id END) * 100 AS percent_los_gt_9_days_not_readmitted
FROM 
  los;