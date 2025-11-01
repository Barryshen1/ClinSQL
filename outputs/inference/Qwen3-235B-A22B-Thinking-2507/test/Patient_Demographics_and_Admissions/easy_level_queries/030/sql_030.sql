WITH first_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 52 AND 62
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY a.subject_id 
    ORDER BY a.admittime
  ) = 1
),
anticoagulant_patients AS (
  SELECT 
    fa.hadm_id,
    TIMESTAMP_DIFF(fa.dischtime, fa.admittime, SECOND) / 86400.0 AS los_days
  FROM first_admissions fa
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    WHERE p.hadm_id = fa.hadm_id
      AND p.drug IS NOT NULL
      AND (
        LOWER(p.drug) LIKE '%warfarin%' OR
        LOWER(p.drug) LIKE '%heparin%' OR
        LOWER(p.drug) LIKE '%enoxaparin%' OR
        LOWER(p.drug) LIKE '%dalteparin%' OR
        LOWER(p.drug) LIKE '%fondaparinux%' OR
        LOWER(p.drug) LIKE '%dabigatran%' OR
        LOWER(p.drug) LIKE '%rivaroxaban%' OR
        LOWER(p.drug) LIKE '%apixaban%' OR
        LOWER(p.drug) LIKE '%edoxaban%' OR
        LOWER(p.drug) LIKE '%betrixaban%'
      )
  )
)
SELECT STDDEV(los_days) AS sd_los
FROM anticoagulant_patients;