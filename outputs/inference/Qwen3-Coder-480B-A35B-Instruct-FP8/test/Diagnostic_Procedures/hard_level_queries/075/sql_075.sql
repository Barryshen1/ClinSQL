WITH dka_admissions AS (
  -- Identify admissions with DKA diagnosis
  SELECT DISTINCT di.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%ketoacidosis%'
),

eligible_patients AS (
  -- Filter patients by gender and age
  SELECT subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients
  WHERE gender = 'M' AND anchor_age BETWEEN 39 AND 49
),

first_icu_stays AS (
  -- Get first ICU stay for each admission
  SELECT
    stay_id,
    hadm_id,
    subject_id,
    intime,
    outtime,
    DATETIME_DIFF(outtime, intime, SECOND) / 86400.0 AS icu_los_days
  FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM physionet-data.mimiciv_3_1_icu.icustays
  ) icu
  WHERE rn = 1
),

procedures_first24 AS (
  -- Count distinct procedures in first 24 hours of ICU stay
  SELECT
    f.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM first_icu_stays f
  JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON f.stay_id = pe.stay_id
    AND pe.starttime >= f.intime
    AND pe.starttime <= DATETIME_ADD(f.intime, INTERVAL 24 HOUR)
  GROUP BY f.stay_id
),

admission_outcomes AS (
  -- Get hospital mortality flag
  SELECT hadm_id, hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.admissions
),

combined_data AS (
  -- Combine all relevant data
  SELECT
    f.stay_id,
    f.icu_los_days,
    COALESCE(p.procedure_count, 0) AS procedure_count,
    a.hospital_expire_flag
  FROM first_icu_stays f
  JOIN eligible_patients ep ON f.subject_id = ep.subject_id
  JOIN dka_admissions da ON f.hadm_id = da.hadm_id
  LEFT JOIN procedures_first24 p ON f.stay_id = p.stay_id
  JOIN admission_outcomes a ON f.hadm_id = a.hadm_id
),

quintiled_data AS (
  -- Stratify into quintiles based on procedure count
  SELECT *,
         NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM combined_data
)

-- Final aggregation by quintile
SELECT
  quintile,
  COUNT(*) AS num_stays,
  AVG(procedure_count) AS mean_procedure_count,
  MIN(procedure_count) AS min_procedure_count,
  MAX(procedure_count) AS max_procedure_count,
  AVG(icu_los_days) AS mean_icu_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS hospital_mortality_percent
FROM quintiled_data
GROUP BY quintile
ORDER BY quintile;