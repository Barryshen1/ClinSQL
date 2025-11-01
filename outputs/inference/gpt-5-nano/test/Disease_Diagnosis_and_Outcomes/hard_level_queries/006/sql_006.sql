WITH lower_gi AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%gastrointestinal bleed%'
     OR LOWER(dd.long_title) LIKE '%hematochezia%'
     OR LOWER(dd.long_title) LIKE '%gastrointestinal hemorrhage%'
),
base AS (
  SELECT a.hadm_id,
         a.subject_id,
         a.admittime,
         a.dischtime,
         p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 70 AND 80
    AND a.hadm_id IN (SELECT hadm_id FROM lower_gi)
),
comorb_flags AS (
  SELECT di.hadm_id,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%hypertension%' OR LOWER(dd.long_title) LIKE '% hypertensive%' THEN 1 ELSE 0 END) AS has_hypertension,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%congestive heart failure%' OR LOWER(dd.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END) AS has_chf,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%renal failure%' OR LOWER(dd.long_title) LIKE '%kidney%' THEN 1 ELSE 0 END) AS has_renal_failure,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%liver%' THEN 1 ELSE 0 END) AS has_liver_disease,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%cancer%' OR LOWER(dd.long_title) LIKE '%malignancy%' THEN 1 ELSE 0 END) AS has_cancer,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%chronic pulmonary%' OR LOWER(dd.long_title) LIKE '%pulmonary disease%' THEN 1 ELSE 0 END) AS has_chronic_pulm
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  GROUP BY di.hadm_id
),
major_complications AS (
  SELECT di.hadm_id,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%sepsis%' THEN 1 ELSE 0 END) AS has_sepsis,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%shock%' THEN 1 ELSE 0 END) AS has_shock,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%acute kidney injury%' OR LOWER(dd.long_title) LIKE '%acute renal failure%' THEN 1 ELSE 0 END) AS has_aki,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%myocardial infarction%' OR LOWER(dd.long_title) LIKE '%heart attack%' THEN 1 ELSE 0 END) AS has_mi,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%stroke%' OR LOWER(dd.long_title) LIKE '%cerebrovascular%' THEN 1 ELSE 0 END) AS has_stroke,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%pulmonary embolism%' THEN 1 ELSE 0 END) AS has_pe,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%gastrointestinal bleed%' OR LOWER(dd.long_title) LIKE '%hemorrhage%' THEN 1 ELSE 0 END) AS has_gi_comp
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  GROUP BY di.hadm_id
)

SELECT
  quintile AS quintile,
  COUNT(*) AS N,
  AVG(mort_90) AS mortality_90_rate,
  AVG(major_comp) AS major_comp_rate,
  CASE WHEN COUNT(LOS_days_survivor) = 0 THEN NULL
       ELSE APPROX_QUANTILES(LOS_days_survivor, 101)[OFFSET(50)]
  END AS median_los_survivors90
FROM (
  SELECT
    s.hadm_id,
    s.subject_id,
    s.admittime,
    s.dischtime,
    s.dod,
    s.LOS_days,
    s.mort_90,
    s.major_comp,
    s.comorb_score,
    CASE WHEN s.mort_90 = 0 THEN s.LOS_days ELSE NULL END AS LOS_days_survivor,
    NTILE(5) OVER (ORDER BY s.comorb_score ASC) AS quintile
  FROM (
    SELECT
      b.hadm_id,
      b.subject_id,
      b.admittime,
      b.dischtime,
      b.dod,
      TIMESTAMP_DIFF(b.dischtime, b.admittime, SECOND) / 86400.0 AS LOS_days,
      CASE
        WHEN b.dod IS NOT NULL
             AND b.dod BETWEEN b.admittime AND TIMESTAMP_ADD(b.admittime, INTERVAL 90 DAY)
        THEN 1 ELSE 0 END AS mort_90,
      CASE
        WHEN (COALESCE(m.has_sepsis,0) = 1
              OR COALESCE(m.has_shock,0) = 1
              OR COALESCE(m.has_aki,0) = 1
              OR COALESCE(m.has_mi,0) = 1
              OR COALESCE(m.has_stroke,0) = 1
              OR COALESCE(m.has_pe,0) = 1
              OR COALESCE(m.has_gi_comp,0) = 1)
        THEN 1 ELSE 0 END AS major_comp,
      COALESCE(cf.has_diabetes,0)
      + COALESCE(cf.has_hypertension,0)
      + COALESCE(cf.has_chf,0)
      + COALESCE(cf.has_renal_failure,0)
      + COALESCE(cf.has_liver_disease,0)
      + COALESCE(cf.has_cancer,0)
      + COALESCE(cf.has_chronic_pulm,0) AS comorb_score
    FROM base b
    LEFT JOIN comorb_flags cf ON b.hadm_id = cf.hadm_id
    LEFT JOIN major_complications m ON b.hadm_id = m.hadm_id
  ) s
) t
GROUP BY quintile
ORDER BY quintile;