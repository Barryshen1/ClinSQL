WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic ON a.hadm_id = ic.hadm_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 70 AND 80
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
      AND d.icd_code LIKE '428%'
    )
),

-- Calculate diagnostic intensity in first 72 hours for patients of interest
diagnostic_intensity_oi AS (
  SELECT 
    poi.stay_id,
    COUNT(DISTINCT CASE 
      WHEN ce.charttime BETWEEN poi.intime AND TIMESTAMP_ADD(poi.intime, INTERVAL 72 HOUR) THEN ce.itemid 
    END) AS num_diagnostics
  FROM 
    patients_of_interest poi
  JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON poi.stay_id = ce.stay_id
  GROUP BY 
    poi.stay_id
),

-- General ICU population
general_icu_population AS (
  SELECT 
    ic.stay_id,
    ic.subject_id,
    ic.hadm_id,
    ic.intime,
    ic.outtime,
    ic.los
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
),

-- Diagnostic intensity for general ICU population
diagnostic_intensity_general AS (
  SELECT 
    gip.stay_id,
    COUNT(DISTINCT CASE 
      WHEN ce.charttime BETWEEN gip.intime AND TIMESTAMP_ADD(gip.intime, INTERVAL 72 HOUR) THEN ce.itemid 
    END) AS num_diagnostics
  FROM 
    general_icu_population gip
  JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON gip.stay_id = ce.stay_id
  GROUP BY 
    gip.stay_id
),

-- Hospital mortality
hospital_mortality AS (
  SELECT 
    a.hadm_id,
    CASE 
      WHEN a.deathtime IS NOT NULL THEN 1 
      ELSE 0 
    END AS hospital_death
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
)

-- Final calculations
SELECT 
  -- Patients of interest
  AVG(di.num_diagnostics) AS mean_diagnostics_oi,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY di.num_diagnostics) AS median_diagnostics_oi,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY di.num_diagnostics) AS p75_diagnostics_oi,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY di.num_diagnostics) AS p95_diagnostics_oi,
  AVG(poi.los) AS mean_icu_los_oi,
  AVG(hm.hospital_death) AS hospital_mortality_oi,
  
  -- General ICU population
  AVG(dig.num_diagnostics) AS mean_diagnostics_general,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dig.num_diagnostics) AS median_diagnostics_general,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY dig.num_diagnostics) AS p75_diagnostics_general,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY dig.num_diagnostics) AS p95_diagnostics_general,
  AVG(gip.los) AS mean_icu_los_general
FROM 
  diagnostic_intensity_oi di
  JOIN patients_of_interest poi ON di.stay_id = poi.stay_id
  JOIN hospital_mortality hm ON poi.hadm_id = hm.hadm_id
  CROSS JOIN 
  general_icu_population gip
  JOIN diagnostic_intensity_general dig ON gip.stay_id = dig.stay_id;