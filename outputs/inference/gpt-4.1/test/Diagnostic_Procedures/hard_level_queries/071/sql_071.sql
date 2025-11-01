WITH female_50_60 AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    p.anchor_age,
    p.gender,
    i.intime,
    i.outtime
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
    JOIN physionet-data.mimiciv_3_1_icu.icustays i ON p.subject_id = i.subject_id
    JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON i.hadm_id = a.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
),

ich_admissions AS (
  -- ICD-10: I61, I62; ICD-9: 431, 432
  SELECT DISTINCT hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  WHERE
    (
      (d.icd_version = 9 AND (d.icd_code LIKE '431%' OR d.icd_code LIKE '432%'))
      OR
      (d.icd_version = 10 AND (d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
    )
),

ich_icu AS (
  SELECT f.*
  FROM female_50_60 f
  JOIN ich_admissions ich ON f.hadm_id = ich.hadm_id
),

first_icu_stays AS (
  -- Only first ICU stay per admission
  SELECT
    subject_id,
    hadm_id,
    MIN(stay_id) AS stay_id,
    MIN(intime) AS intime
  FROM
    physionet-data.mimiciv_3_1_icu.icustays
  GROUP BY subject_id, hadm_id
),

procedure_burden AS (
  -- Count ICU procedures in first 72h for each ICU stay
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    COUNT(DISTINCT p.itemid) AS proc_count
  FROM
    ich_icu i
    JOIN first_icu_stays fs ON i.subject_id = fs.subject_id AND i.hadm_id = fs.hadm_id AND i.stay_id = fs.stay_id
    LEFT JOIN physionet-data.mimiciv_3_1_icu.procedureevents p
      ON i.subject_id = p.subject_id
      AND i.hadm_id = p.hadm_id
      AND i.stay_id = p.stay_id
      AND p.starttime >= i.intime
      AND p.starttime < DATETIME_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY i.subject_id, i.hadm_id, i.stay_id
),

-- General ICU cohort (female, 50-60, first ICU stay per admission)
general_icu AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime
  FROM
    female_50_60 f
    JOIN first_icu_stays fs ON f.subject_id = fs.subject_id AND f.hadm_id = fs.hadm_id AND f.stay_id = fs.stay_id
),

-- Hospital LOS and mortality for both cohorts
hospital_outcomes AS (
  SELECT
    g.subject_id,
    g.hadm_id,
    CASE WHEN i.hadm_id IS NOT NULL THEN 'ICH' ELSE 'General' END AS cohort,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24.0 AS hospital_los,
    a.hospital_expire_flag
  FROM
    general_icu g
    JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON g.hadm_id = a.hadm_id
    LEFT JOIN ich_admissions i ON g.hadm_id = i.hadm_id
)

-- Final output
SELECT
  'ICH cohort: ICU procedure burden in first 72h' AS section,
  APPROX_QUANTILES(proc_count, 100)[25] AS percentile_25,
  APPROX_QUANTILES(proc_count, 100)[50] AS percentile_50,
  APPROX_QUANTILES(proc_count, 100)[90] AS percentile_90,
  MAX(proc_count) AS max_proc_count
FROM procedure_burden

UNION ALL

SELECT
  'Hospital LOS (days): ICH vs General ICU' AS section,
  AVG(CASE WHEN cohort = 'ICH' THEN hospital_los END) AS ich_avg_los,
  AVG(CASE WHEN cohort = 'General' THEN hospital_los END) AS general_avg_los,
  NULL AS percentile_90,
  NULL AS max_proc_count
FROM hospital_outcomes

UNION ALL

SELECT
  'In-hospital mortality: ICH vs General ICU' AS section,
  AVG(CASE WHEN cohort = 'ICH' THEN hospital_expire_flag END) AS ich_mortality_rate,
  AVG(CASE WHEN cohort = 'General' THEN hospital_expire_flag END) AS general_mortality_rate,
  NULL AS percentile_90,
  NULL AS max_proc_count
FROM hospital_outcomes;