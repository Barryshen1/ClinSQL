WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 85 AND 95
),
icu_stays AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    ie.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN patients_filtered pf
    ON ie.subject_id = pf.subject_id
),
arf_diagnoses AS (
  SELECT 
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND icd_code LIKE 'J96.0%')
     OR (icd_version = 9 AND icd_code = '51881')
  GROUP BY hadm_id
),
target_population AS (
  SELECT 
    is1.subject_id,
    is1.hadm_id,
    is1.stay_id,
    is1.intime,
    is1.los
  FROM icu_stays is1
  INNER JOIN arf_diagnoses ad
    ON is1.hadm_id = ad.hadm_id
),
vital_sign_scores AS (
  SELECT 
    tp.*,
    COUNT(ce.charttime) AS instability_score,
    a.hospital_expire_flag
  FROM target_population tp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON tp.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON tp.stay_id = ce.stay_id
    AND ce.charttime BETWEEN tp.intime AND DATETIME_ADD(tp.intime, INTERVAL 24 HOUR)
  GROUP BY tp.subject_id, tp.hadm_id, tp.stay_id, tp.intime, tp.los, a.hospital_expire_flag
),
quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY instability_score DESC) AS quartile
  FROM vital_sign_scores
)
SELECT 
  (SELECT (COUNTIF(instability_score <= 85) * 100.0) / COUNT(*) 
   FROM vital_sign_scores) AS percentile_rank,
  (SELECT AVG(los) 
   FROM quartiles 
   WHERE quartile = 1) AS avg_los,
  (SELECT AVG(hospital_expire_flag) 
   FROM quartiles 
   WHERE quartile = 1) AS mortality_rate;