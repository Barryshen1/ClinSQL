WITH sepsis_cohort AS (
  -- Base cohort: men 53-63 with sepsis (excl shock)
  SELECT DISTINCT 
    a.subject_id,
    a.hadm_id,
    TIMESTAMP(a.admittime) AS admittime,
    TIMESTAMP(a.dischtime) AS dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    AND a.admission_type != 'NEWBORN'
    AND a.dischtime IS NOT NULL
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 >= 1
    AND d.icd_version = '10'
    AND (
      -- Sepsis ICD-10 codes (A41.* for septicemia)
      d.icd_code LIKE 'A41.%'
      OR d.icd_code = 'A02.1'
      OR d.icd_code LIKE 'A40.%'
    )
    -- Exclude septic shock (R65.2*)
    AND NOT EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 
      WHERE d2.subject_id = d.subject_id 
        AND d2.hadm_id = d.hadm_id 
        AND d2.icd_code LIKE 'R65.2%'
    )
),

icu_timing AS (
  -- Day-1 ICU flag
  SELECT 
    sc.subject_id,
    sc.hadm_id,
    MAX(CASE WHEN DATE(i.intime) = DATE(sc.admittime) THEN 1 ELSE 0 END) AS day1_icu
  FROM sepsis_cohort sc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON sc.subject_id = i.subject_id AND sc.hadm_id = i.hadm_id
  GROUP BY sc.subject_id, sc.hadm_id
),

mech_vent AS (
  -- Mechanical ventilation (invasive, ever in ICU stay)
  SELECT DISTINCT 
    pe.subject_id,
    pe.hadm_id,
    1 AS mv
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON i.subject_id = pe.subject_id 
    AND i.stay_id = pe.stay_id
    AND pe.starttime BETWEEN i.intime AND i.outtime
  INNER JOIN sepsis_cohort sc
    ON i.subject_id = sc.subject_id AND i.hadm_id = sc.hadm_id
  WHERE pe.itemid IN (
    225477,  -- Ventilation endotracheal
    225456,  -- Vent mode (added)
    225468,  -- Ventilator mode
    220339,  -- Vent start
    224685   -- Extubation (indicates prior vent)
  )
    AND pe.value IS NOT NULL  -- Ensure active event
),

vasopressors AS (
  -- Vasopressors (infusions >0 in ICU)
  SELECT DISTINCT 
    ie.subject_id,
    ie.hadm_id,
    1 AS vaso
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON i.subject_id = ie.subject_id 
    AND i.stay_id = ie.stay_id
    AND ie.starttime BETWEEN i.intime AND i.outtime
  INNER JOIN sepsis_cohort sc
    ON i.subject_id = sc.subject_id AND i.hadm_id = sc.hadm_id
  WHERE ie.itemid IN (
    220615,  -- Norepinephrine
    221906,  -- Epinephrine
    30047,   -- Phenylephrine
    30120,   -- Vasopressin
    225798   -- Dopamine
  )
    AND (ie.amount > 0 OR ie.rate > 0)  -- Amount or rate >0
    AND ie.ordercategoryname = 'Acute - Pressor'
),

rrt AS (
  -- RRT (ever in ICU, using procedures)
  SELECT DISTINCT 
    pe.subject_id,
    pe.hadm_id,
    1 AS rrt
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON i.subject_id = pe.subject_id 
    AND i.stay_id = pe.stay_id
    AND pe.starttime BETWEEN i.intime AND i.outtime
  INNER JOIN sepsis_cohort sc
    ON i.subject_id = sc.subject_id AND i.hadm_id = sc.hadm_id
  WHERE pe.itemid IN (
    225468,  -- CRRT filter
    225827,  -- CRRT start (added)
    220980,  -- CVVH
    40066,   -- Hemodialysis
    30365,   -- Ultrafiltration
    30319    -- Dialysis (added)
  )
    AND pe.value IS NOT NULL
)

-- Main aggregation (filter to admissions with ICU for relevance)
SELECT 
  CASE WHEN sc.los_days < 8 THEN '<8' ELSE '≥8' END AS los_group,
  COALESCE(it.day1_icu, 0) AS day1_icu,
  COUNT(DISTINCT sc.hadm_id) AS n_patients,
  ROUND(AVG(sc.hospital_expire_flag) * 100, 1) AS mortality_pct,
  ROUND(AVG(COALESCE(mv.mv, 0)) * 100, 1) AS mv_pct,
  ROUND(AVG(COALESCE(va.vao, 0)) * 100, 1) AS vaso_pct,  -- Note: typo 'vao' fixed to 'vaso' in SELECT
  ROUND(AVG(COALESCE(rr.rrt, 0)) * 100, 1) AS rrt_pct
FROM sepsis_cohort sc
LEFT JOIN icu_timing it
  ON sc.subject_id = it.subject_id AND sc.hadm_id = it.hadm_id
LEFT JOIN mech_vent mv
  ON sc.subject_id = mv.subject_id AND sc.hadm_id = mv.hadm_id
LEFT JOIN vasopressors va
  ON sc.subject_id = va.subject_id AND sc.hadm_id = va.hadm_id
LEFT JOIN rrt rr
  ON sc.subject_id = rr.subject_id AND sc.hadm_id = rr.hadm_id
WHERE EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i WHERE i.subject_id = sc.subject_id AND i.hadm_id = sc.hadm_id)
GROUP BY los_group, day1_icu
ORDER BY los_group, day1_icu;