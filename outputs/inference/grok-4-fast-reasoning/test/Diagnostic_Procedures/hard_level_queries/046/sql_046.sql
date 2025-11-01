WITH first_stays AS (
  -- All first ICU stays
  SELECT subject_id, hadm_id, stay_id, intime, outtime, los,
         ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu`.icustays
  WHERE intime IS NOT NULL
  QUALIFY rn = 1
),
ards_hadms AS (
  -- HADMs with ARDS diagnosis (any position)
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
  WHERE icd_code IN ('5185', '51851', '51852', 'J80', 'J9600', 'J9601', 'J9602')
    AND icd_version IN (9, 10)
),
stay_procs AS (
  -- Distinct procedures in first 72h per first stay
  SELECT 
    fs.subject_id, fs.hadm_id, fs.stay_id, fs.intime,
    COUNT(DISTINCT pe.itemid) AS num_distinct_procs
  FROM first_stays fs
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents pe
    ON fs.subject_id = pe.subject_id
    AND fs.hadm_id = pe.hadm_id
    AND fs.stay_id = pe.stay_id
    AND pe.starttime >= fs.intime
    AND pe.starttime < DATETIME_ADD(fs.intime, INTERVAL 72 HOUR)
  GROUP BY fs.subject_id, fs.hadm_id, fs.stay_id, fs.intime
),
ards_cohort AS (
  -- ARDS cohort: first stays + filters
  SELECT 
    sp.*,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los_days,
    a.hospital_expire_flag
  FROM stay_procs sp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON sp.subject_id = p.subject_id
  INNER JOIN ards_hadms ah
    ON sp.subject_id = ah.subject_id AND sp.hadm_id = ah.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON sp.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
),
all_cohort AS (
  -- All first ICU stays
  SELECT 
    sp.*,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los_days,
    a.hospital_expire_flag
  FROM stay_procs sp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON sp.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON sp.hadm_id = a.hadm_id
),
-- Aggregations for ARDS cohort
ards_agg AS (
  SELECT 
    MIN(num_distinct_procs) AS min_procs,
    APPROX_QUANTILES(num_distinct_procs, 4)[OFFSET(2)] AS p75_procs,
    APPROX_QUANTILES(num_distinct_procs, 10)[OFFSET(8)] AS p90_procs,
    AVG(hospital_los_days) AS mean_hospital_los,
    AVG(hospital_expire_flag * 1.0) AS mortality_rate
  FROM ards_cohort
),
-- Aggregations for all cohort
all_agg AS (
  SELECT 
    MIN(num_distinct_procs) AS min_procs,
    APPROX_QUANTILES(num_distinct_procs, 4)[OFFSET(2)] AS p75_procs,
    APPROX_QUANTILES(num_distinct_procs, 10)[OFFSET(8)] AS p90_procs,
    AVG(hospital_los_days) AS mean_hospital_los,
    AVG(hospital_expire_flag * 1.0) AS mortality_rate
  FROM all_cohort
)
-- Combine results
SELECT 'ARDS female 37-47 (first ICU stay)' AS cohort, min_procs, p75_procs, p90_procs, mean_hospital_los, mortality_rate
FROM ards_agg
UNION ALL
SELECT 'All ICU patients (first ICU stay)' AS cohort, min_procs, p75_procs, p90_procs, mean_hospital_los, mortality_rate
FROM all_agg;