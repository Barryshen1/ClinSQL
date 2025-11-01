WITH
-- 1) Select lab itemids of interest by matching d_labitems.label
lab_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%creatinine%' OR
    LOWER(label) LIKE '%sodium%' OR
    LOWER(label) LIKE '%potassium%' OR
    LOWER(label) LIKE '%chloride%' OR
    LOWER(label) LIKE '%bicarbonate%' OR
    LOWER(label) LIKE '%carbon dioxide%' OR
    LOWER(label) LIKE '%co2%' OR
    LOWER(label) LIKE '%glucose%' OR
    LOWER(label) LIKE '%hemoglobin%' OR
    LOWER(label) LIKE '%haemoglobin%' OR
    LOWER(label) LIKE '%white blood cell%' OR
    LOWER(label) LIKE '%wbc%' OR
    LOWER(label) LIKE '%platelet%' OR
    LOWER(label) LIKE '%platelets%' OR
    LOWER(label) LIKE '%lactate%'
),

-- 2) For each admission and each lab item, compute max and min valuenum within first 72 hours
lab_deltas AS (
  SELECT
    le.hadm_id,
    le.itemid,
    MAX(le.valuenum) AS max_val,
    MIN(le.valuenum) AS min_val
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad
    ON le.hadm_id = ad.hadm_id
  JOIN lab_items li
    ON le.itemid = li.itemid
  WHERE
    le.valuenum IS NOT NULL
    AND le.charttime BETWEEN ad.admittime AND TIMESTAMP_ADD(ad.admittime, INTERVAL 72 HOUR)
  GROUP BY le.hadm_id, le.itemid
),

-- 3) Sum absolute deltas across lab items per admission => instability score
instability_per_adm AS (
  SELECT
    hadm_id,
    SUM(ABS(max_val - min_val)) AS instability_score
  FROM lab_deltas
  GROUP BY hadm_id
),

-- 4) Identify admissions with AKI by matching diagnosis descriptions
aki_admissions AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE dd.long_title IS NOT NULL
    AND (
      LOWER(dd.long_title) LIKE '%acute kidney%' OR
      LOWER(dd.long_title) LIKE '%acute renal%'
    )
),

-- 5) Prepare admissions joined with patient demographics, instability score, ICU flag, los, mortality
admission_level AS (
  SELECT
    ad.hadm_id,
    ad.subject_id,
    p.gender,
    p.anchor_age,
    ad.admittime,
    ad.dischtime,
    ad.hospital_expire_flag,
    COALESCE(inst.instability_score, 0.0) AS instability_score,
    -- ICU flag: 1 if any icustays row exists for the hadm_id
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
      WHERE icu.hadm_id = ad.hadm_id
    ) THEN 1 ELSE 0 END AS had_icu,
    -- hospital LOS in days (fractional)
    TIMESTAMP_DIFF(ad.dischtime, ad.admittime, HOUR) / 24.0 AS los_days,
    -- AKI flag
    CASE WHEN aki.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_aki
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ad.subject_id = p.subject_id
  LEFT JOIN instability_per_adm inst
    ON ad.hadm_id = inst.hadm_id
  LEFT JOIN aki_admissions aki
    ON ad.hadm_id = aki.hadm_id
  -- Restrict to inpatient admissions; filter to male and age 47-57 will be applied in the final step
)

-- Final aggregation: compare AKI vs age-matched male controls
SELECT
  CASE WHEN is_aki = 1 THEN 'AKI' ELSE 'No_AKI' END AS cohort,
  COUNT(*) AS n_admissions,
  ROUND(AVG(instability_score), 3) AS mean_72h_lab_instability_score,
  ROUND(100.0 * SUM(had_icu) / COUNT(*), 2) AS percent_with_icu_stay,
  ROUND(AVG(los_days), 2) AS avg_hospital_los_days,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS in_hospital_mortality_percent
FROM admission_level
WHERE
  gender = 'M'
  AND anchor_age BETWEEN 47 AND 57
GROUP BY is_aki
ORDER BY is_aki DESC;