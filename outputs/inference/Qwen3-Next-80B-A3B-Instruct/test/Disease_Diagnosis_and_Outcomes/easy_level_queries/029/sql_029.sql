WITH filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
),
ugib_diagnoses AS (
  SELECT DISTINCT di.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE 
    LOWER(d.long_title) LIKE '%gastrointestinal bleeding%'
    OR LOWER(d.long_title) LIKE '%upper gi bleed%'
    OR LOWER(d.long_title) LIKE '%upper gastrointestinal hemorrhage%'
    OR LOWER(d.long_title) LIKE '%peptic ulcer hemorrhage%'
    OR LOWER(d.long_title) LIKE '%hemorrhage from gastric ulcer%'
    OR LOWER(d.long_title) LIKE '%hemorrhage from duodenal ulcer%'
    OR LOWER(d.long_title) LIKE '%hemorrhage from esophageal varices%'
    OR LOWER(d.long_title) LIKE '%hemorrhage from esophagitis%'
    OR LOWER(d.long_title) LIKE '%hemorrhage from mallory-weiss%'
    OR LOWER(d.long_title) LIKE '%hemorrhage from gastritis%'
    OR LOWER(d.long_title) LIKE '%hemorrhage from angiodysplasia%'
    OR LOWER(d.long_title) LIKE '%hemorrhage from colitis%'
    OR LOWER(d.long_title) LIKE '%hemorrhage from diverticulum%'
    OR LOWER(d.long_title) LIKE '%hemorrhage from rectum%'
    OR LOWER(d.long_title) LIKE '%hemorrhage from anorectal%'
    OR LOWER(d.long_title) LIKE '%hemorrhage from intestinal%'
    OR LOWER(d.long_title) LIKE '%hemorrhage from small bowel%'
    OR LOWER(d.long_title) LIKE '%hemorrhage from colon%'
    OR LOWER(d.long_title) LIKE '%hemorrhage from ileum%'
    OR LOWER(d.long_title) LIKE '%hemorrhage from jejunum%'
    OR LOWER(d.long_title) LIKE '%hemorrhage from duodenum%'
    OR LOWER(d.long_title) LIKE '%hemorrhage from stomach%'
    OR LOWER(d.long_title) LIKE '%hemorrhage from esophagus%'
    OR LOWER(d.long_title) LIKE '%gi hemorrhage%'
    OR LOWER(d.long_title) LIKE '%ugib%'
    OR LOWER(d.long_title) LIKE '%upper gi bleeding%'
    OR LOWER(d.long_title) LIKE '%acute upper gi bleeding%'
    OR LOWER(d.long_title) LIKE '%acute gi bleeding%'
    OR LOWER(d.long_title) LIKE '%acute upper gastrointestinal bleeding%'
    OR LOWER(d.long_title) LIKE '%acute upper gi hemorrhage%'
    OR LOWER(d.long_title) LIKE '%acute gi hemorrhage%'
),
copd_exacerbation_diagnoses AS (
  SELECT DISTINCT di.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE 
    LOWER(d.long_title) LIKE '%copd%'
    AND (
      LOWER(d.long_title) LIKE '%exacerbation%'
      OR LOWER(d.long_title) LIKE '%acute exacerbation%'
      OR LOWER(d.long_title) LIKE '%acute flare%'
      OR LOWER(d.long_title) LIKE '%worsening%'
    )
),
both_conditions AS (
  SELECT fa.los_days
  FROM filtered_admissions fa
  INNER JOIN ugib_diagnoses u ON fa.hadm_id = u.hadm_id
  INNER JOIN copd_exacerbation_diagnoses c ON fa.hadm_id = c.hadm_id
)
SELECT 
  PERCENTILE_DISC(los_days, 0.5) AS median_los_days
FROM both_conditions;