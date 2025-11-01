WITH first_icu AS (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
target_population AS (
  SELECT i.stay_id
  FROM first_icu i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  WHERE i.rn = 1
    AND p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 37 AND 47
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = i.hadm_id
        AND d.icd_code = 'J80'
        AND d.icd_version = 10
    )
),
icu_procedures AS (
  SELECT i.stay_id, 
         COUNT(DISTINCT pe.itemid) AS proc_count
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON i.stay_id = pe.stay_id
    AND pe.starttime >= i.intime
    AND pe.starttime <= i.intime + INTERVAL '72' HOUR
  GROUP BY i.stay_id
),
target_procedure_stats AS (
  SELECT MIN(proc_count) AS target_min_procedures
  FROM icu_procedures
  WHERE stay_id IN (SELECT stay_id FROM target_population)
),
entire_population_procedure_stats AS (
  SELECT 
    APPROX_QUANTILES(proc_count, 1000)[OFFSET(749)] AS p75,
    APPROX_QUANTILES(proc_count, 1000)[OFFSET(899)] AS p90
  FROM icu_procedures
),
hospital_outcomes AS (
  SELECT 
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE hadm_id IN (
    SELECT DISTINCT hadm_id 
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  )
)
SELECT 
  (SELECT target_min_procedures FROM target_procedure_stats) AS target_min_procedures,
  (SELECT p75 FROM entire_population_procedure_stats) AS entire_pop_p75,
  (SELECT p90 FROM entire_population_procedure_stats) AS entire_pop_p90,
  (SELECT mean_los_days FROM hospital_outcomes) AS entire_pop_mean_los,
  (SELECT mortality_rate FROM hospital_outcomes) AS entire_pop_mortality;