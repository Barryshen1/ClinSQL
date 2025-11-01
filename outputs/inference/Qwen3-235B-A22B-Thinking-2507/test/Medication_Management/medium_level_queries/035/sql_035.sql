WITH 
admissions_with_age AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),
cohort_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM admissions_with_age a
  WHERE 
    a.gender = 'F'
    AND a.age_at_adm BETWEEN 57 AND 67
    AND a.dischtime IS NOT NULL
),
cohort_with_conditions AS (
  SELECT 
    ca.hadm_id,
    ca.admittime,
    ca.dischtime
  FROM cohort_admissions ca
  WHERE 
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = ca.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%')
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%' OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%'))
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = ca.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),
cohort_with_prescriptions AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    MAX(CASE 
          WHEN p.starttime >= c.admittime 
            AND p.starttime < DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
            AND REGEXP_CONTAINS(LOWER(p.drug), r'exenatide|byetta|bydureon|liraglutide|victoza|saxenda|semaglutide|ozempic|rybelsus|wegovy|dulaglutide|trulicity|lixisenatide|adlyxin')
          THEN 1 
          ELSE 0 
        END) AS has_first_48h,
    MAX(CASE 
          WHEN p.starttime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR)
            AND p.starttime < c.dischtime
            AND REGEXP_CONTAINS(LOWER(p.drug), r'exenatide|byetta|bydureon|liraglutide|victoza|saxenda|semaglutide|ozempic|rybelsus|wegovy|dulaglutide|trulicity|lixisenatide|adlyxin')
          THEN 1 
          ELSE 0 
        END) AS has_final_12h
  FROM cohort_with_conditions c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  GROUP BY c.hadm_id, c.admittime, c.dischtime
)
SELECT 
  COUNT(*) AS total_admissions,
  SUM(has_first_48h) AS count_first_48h,
  SUM(has_final_12h) AS count_final_12h,
  (SUM(has_first_48h) * 100.0 / COUNT(*)) AS prevalence_first_48h,
  (SUM(has_final_12h) * 100.0 / COUNT(*)) AS prevalence_final_12h,
  ( (SUM(has_final_12h) * 100.0 / COUNT(*)) - (SUM(has_first_48h) * 100.0 / COUNT(*)) ) AS absolute_change,
  ( ( (SUM(has_final_12h) * 100.0 / COUNT(*)) - (SUM(has_first_48h) * 100.0 / COUNT(*)) ) 
    / NULLIF((SUM(has_first_48h) * 100.0 / COUNT(*)), 0) 
  ) AS relative_change
FROM cohort_with_prescriptions;