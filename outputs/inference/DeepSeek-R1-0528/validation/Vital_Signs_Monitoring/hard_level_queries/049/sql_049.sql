WITH cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.los,
    adm.hospital_expire_flag,
    inst.instability_score
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  INNER JOIN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      (icd_version = 9 AND (icd_code LIKE '038%' OR icd_code IN ('785.52', '995.91', '995.92')))
      OR (icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%' OR icd_code IN ('R65.20', 'R65.21')))
    GROUP BY hadm_id
  ) sepsis
    ON ie.hadm_id = sepsis.hadm_id
  INNER JOIN `my_project.my_dataset.instability_scores` inst  -- USER MUST REPLACE WITH ACTUAL TABLE
    ON ie.stay_id = inst.stay_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year)) BETWEEN 78 AND 88
),
percentile_85 AS (
  SELECT 
    (COUNTIF(instability_score <= 85) * 100.0 / COUNT(*)) AS percentile_rank
  FROM cohort
),
quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY instability_score DESC) AS instab_quartile
  FROM cohort
),
quartile4_stays AS (
  SELECT los
  FROM quartiles
  WHERE instab_quartile = 4
),
quartile4_admissions AS (
  SELECT 
    hadm_id,
    MAX(hospital_expire_flag) AS hospital_expire_flag
  FROM quartiles
  WHERE instab_quartile = 4
  GROUP BY hadm_id
)
SELECT 
  (SELECT percentile_rank FROM percentile_85) AS percentile_rank_of_85,
  (SELECT AVG(los) FROM quartile4_stays) AS mean_icu_los_quartile4,
  (SELECT AVG(hospital_expire_flag) FROM quartile4_admissions) AS hospital_mortality_rate_quartile4;