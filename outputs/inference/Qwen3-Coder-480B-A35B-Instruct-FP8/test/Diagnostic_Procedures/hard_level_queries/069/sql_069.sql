WITH pe_admissions AS (
  -- Identify admissions with PE diagnosis
  SELECT DISTINCT
    di.subject_id,
    di.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    (d.icd_version = 9 AND d.icd_code LIKE '415.1%')
    OR
    (d.icd_version = 10 AND d.icd_code LIKE 'I26%')
),

eligible_patients AS (
  -- Filter patients by age and gender
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  WHERE
    p.anchor_age BETWEEN 44 AND 54
    AND p.gender = 'M'
),

first_icu_stays AS (
  -- Get first ICU stay for each subject
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    a.dischtime,
    a.hospital_expire_flag
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM
      physionet-data.mimiciv_3_1_icu.icustays
  ) i
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON i.hadm_id = a.hadm_id
  WHERE
    i.rn = 1
),

icu_procedures AS (
  -- Count distinct procedures in first 72 hours of ICU stay
  SELECT
    f.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM
    first_icu_stays f
  JOIN
    physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON f.stay_id = pe.stay_id
  WHERE
    pe.starttime >= f.intime
    AND pe.starttime <= DATETIME_ADD(f.intime, INTERVAL 72 HOUR)
  GROUP BY
    f.stay_id
),

all_first_stays_with_procedures AS (
  -- Include all first ICU stays, even with 0 procedures
  SELECT
    f.stay_id,
    f.hadm_id,
    f.intime,
    f.dischtime,
    f.hospital_expire_flag,
    COALESCE(p.procedure_count, 0) AS procedure_count
  FROM
    first_icu_stays f
  LEFT JOIN
    icu_procedures p
    ON f.stay_id = p.stay_id
),

quintile_stratified AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM
    all_first_stays_with_procedures
)

SELECT
  quintile,
  AVG(procedure_count) AS avg_procedure_count,
  AVG(DATETIME_DIFF(dischtime, intime, HOUR) / 24.0) AS avg_hospital_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_percent
FROM
  quintile_stratified
GROUP BY
  quintile
ORDER BY
  quintile;