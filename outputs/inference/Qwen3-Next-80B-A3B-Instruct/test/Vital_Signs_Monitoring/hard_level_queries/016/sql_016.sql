WITH transplant_patients AS (
  SELECT DISTINCT i.stay_id
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON i.hadm_id = a.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE LOWER(did.long_title) LIKE '%transplant%' 
     OR LOWER(did.long_title) LIKE '%graft%'
     OR did.icd_code LIKE 'Z94.%'
     OR LOWER(did.long_title) LIKE '%organ transplant%'
     OR LOWER(did.long_title) LIKE '%transplanted%'
),

icu_cohort AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    p.gender,
    p.anchor_age,
    CASE WHEN tp.stay_id IS NOT NULL THEN 1 ELSE 0 END AS is_transplant,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON i.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON i.hadm_id = a.hadm_id
  LEFT JOIN transplant_patients tp ON i.stay_id = tp.stay_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 57 AND 67
),

instability_events AS (
  SELECT 
    ce.stay_id,
    COUNT(*) AS instability_count
  FROM physionet-data.mimiciv_3_1_icu.chartevents ce
  JOIN icu_cohort ic ON ce.stay_id = ic.stay_id
  JOIN physionet-data.mimiciv_3_1_icu.d_items di ON ce.itemid = di.itemid
  WHERE ce.charttime >= ic.intime 
    AND ce.charttime <= ic.intime + INTERVAL 72 HOUR
    AND (
      (LOWER(di.label) LIKE '%temperature%' AND ce.valuenum > 38.5)
      OR ((LOWER(di.label) LIKE '%spo2%' OR LOWER(di.label) LIKE '%o2 sat%' OR LOWER(di.label) LIKE '%saturation%') AND ce.valuenum < 90)
      OR ((LOWER(di.label) LIKE '%respiratory rate%' OR LOWER(di.label) LIKE '%rr%') AND ce.valuenum > 20)
    )
  GROUP BY ce.stay_id
)

SELECT 
  ic.is_transplant,
  AVG(ic.hospital_expire_flag) AS mortality_rate,
  AVG(ic.los) AS avg_los,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY COALESCE(ie.instability_count, 0)) AS median_instability_score,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY COALESCE(ie.instability_count, 0)) AS p25_instability_score,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY COALESCE(ie.instability_count, 0)) AS p75_instability_score,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ic.los) AS median_los,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY ic.los) AS p25_los,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY ic.los) AS p75_los,
  COUNT(*) AS n_patients
FROM icu_cohort ic
LEFT JOIN instability_events ie ON ic.stay_id = ie.stay_id
GROUP BY ic.is_transplant
ORDER BY ic.is_transplant;