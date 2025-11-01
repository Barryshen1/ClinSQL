WITH gi_bleed_admissions AS (
  SELECT 
      diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
      ON diag.icd_code = d.icd_code 
      AND diag.icd_version = d.icd_version
  WHERE 
      diag.seq_num = 1  -- Primary diagnosis
      AND (
        LOWER(d.long_title) LIKE '%upper%gi%bleed%' OR
        LOWER(d.long_title) LIKE '%gastric%hemorrhage%' OR
        LOWER(d.long_title) LIKE '%duodenal%hemorrhage%' OR
        LOWER(d.long_title) LIKE '%esophageal%varices%bleeding%' OR
        LOWER(d.long_title) LIKE '%hematemesis%' OR
        LOWER(d.long_title) LIKE '%melena%'
      )
),
target_admissions AS (
  SELECT 
      a.hadm_id,
      DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  INNER JOIN gi_bleed_admissions g 
      ON a.hadm_id = g.hadm_id
  WHERE 
      p.gender = 'M'
      AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) = 70
)
SELECT 
    DISTINCT PERCENTILE_CONT(los_days, 0.75) OVER () AS percentile_75_los_days
FROM target_admissions;