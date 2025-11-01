WITH admissions_with_pe AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code = '4151')  -- ICD-9: Pulmonary embolism
    OR (icd_version = 10 AND icd_code LIKE 'I26%')  -- ICD-10: Pulmonary embolism codes
),
base_population AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    -- Compute age at admission (MIMIC-IV standard approximation)
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN admissions_with_pe pe
    ON a.hadm_id = pe.hadm_id
  WHERE
    p.gender = 'F'  -- Female patients only
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 65 AND 75
),
first_icu_stays AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.los,
    bp.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS stay_order
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN base_population bp
    ON i.hadm_id = bp.hadm_id
  WHERE i.first_careunit IS NOT NULL  -- Ensure valid ICU stay
),
procedure_counts AS (
  SELECT
    fis.stay_id,
    COUNT(*) AS procedure_count
  FROM first_icu_stays fis
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON fis.stay_id = pe.stay_id
    AND pe.starttime >= fis.intime
    AND pe.starttime <= fis.intime + INTERVAL '72' HOUR
  WHERE 
    pe.ordercategoryname IN ('Diagnostic Imaging', 'Diagnostic Testing')
  GROUP BY fis.stay_id
),
quartile_data AS (
  SELECT
    fis.stay_id,
    COALESCE(pc.procedure_count, 0) AS procedure_count,
    fis.los,
    fis.hospital_expire_flag,
    NTILE(4) OVER (ORDER BY COALESCE(pc.procedure_count, 0)) AS quartile
  FROM first_icu_stays fis
  LEFT JOIN procedure_counts pc
    ON fis.stay_id = pc.stay_id
  WHERE fis.stay_order = 1  -- Only first ICU stay
)
SELECT
  quartile,
  COUNT(*) AS N,
  ROUND(AVG(procedure_count), 2) AS mean_procedure_count,
  ROUND(AVG(los), 2) AS mean_icu_los_days,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS hospital_mortality_pct
FROM quartile_data
GROUP BY quartile
ORDER BY quartile;