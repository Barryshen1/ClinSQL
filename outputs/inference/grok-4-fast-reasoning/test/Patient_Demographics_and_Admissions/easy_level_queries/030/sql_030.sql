WITH first_adms AS (
  SELECT 
    subject_id, 
    hadm_id, 
    admittime, 
    dischtime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
eligible_adms AS (
  SELECT 
    f.*,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    DATE_DIFF(f.dischtime, f.admittime, DAY) AS los
  FROM first_adms f
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON f.subject_id = p.subject_id
  WHERE f.rn = 1
    AND p.gender = 'F'
    AND f.dischtime > f.admittime
),
aged_adms AS (
  SELECT 
    *,
    anchor_age + EXTRACT(YEAR FROM admittime) - anchor_year AS age_at_admit
  FROM eligible_adms
  WHERE anchor_age + EXTRACT(YEAR FROM admittime) - anchor_year BETWEEN 52 AND 62
),
anticoag_adms AS (
  SELECT a.*
  FROM aged_adms a
  WHERE EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    WHERE pres.subject_id = a.subject_id
      AND pres.hadm_id = a.hadm_id
      AND (
        LOWER(pres.drug) LIKE '%heparin%' OR
        LOWER(pres.drug) LIKE '%enoxaparin%' OR
        LOWER(pres.drug) LIKE '%warfarin%' OR
        LOWER(pres.drug) LIKE '%dalteparin%' OR
        LOWER(pres.drug) LIKE '%tinzaparin%' OR
        LOWER(pres.drug) LIKE '%fondaparinux%' OR
        LOWER(pres.drug) LIKE '%argatroban%' OR
        LOWER(pres.drug) LIKE '%bivalirudin%' OR
        LOWER(pres.drug) LIKE '%desirudin%' OR
        LOWER(pres.drug) LIKE '%lepirudin%' OR
        LOWER(pres.drug) LIKE '%rivaroxaban%' OR
        LOWER(pres.drug) LIKE '%apixaban%' OR
        LOWER(pres.drug) LIKE '%dabigatran%' OR
        LOWER(pres.drug) LIKE '%edoxaban%'
      )
  )
)
SELECT STDDEV(los) AS sd_los_days
FROM anticoag_adms;