WITH age_calc AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS admission_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE a.dischtime > a.admittime  -- Ensure valid LOS
),
bleed_adms AS (
  SELECT 
    ac.*,
    TIMESTAMP_DIFF(ac.dischtime, ac.admittime, DAY) AS los
  FROM age_calc ac
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ac.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code 
    AND di.icd_version = dd.icd_version
  WHERE di.seq_num = 1
    AND (
      LOWER(dd.long_title) LIKE '%upper gastrointestinal hemorrhage%'
      OR LOWER(dd.long_title) LIKE '%hematemesis%'
      OR (LOWER(dd.long_title) LIKE '%gastric%' AND LOWER(dd.long_title) LIKE '%hemorrhage%')
      OR (LOWER(dd.long_title) LIKE '%duodenal%' AND LOWER(dd.long_title) LIKE '%hemorrhage%')
      OR (LOWER(dd.long_title) LIKE '%esophageal%' AND LOWER(dd.long_title) LIKE '%hemorrhage%')
      OR (LOWER(dd.long_title) LIKE '%varice%' AND LOWER(dd.long_title) LIKE '%bleed%')
      OR (LOWER(dd.long_title) LIKE '%gastritis%' AND LOWER(dd.long_title) LIKE '%hemorrhage%')
      OR LOWER(dd.long_title) LIKE '%mallory%'
    )
)
SELECT 
  APPROX_QUANTILES(los, 4)[OFFSET(3)] AS p75_los_days
FROM bleed_adms
WHERE gender = 'M'
  AND admission_age = 70;