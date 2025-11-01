WITH pe_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '4151%')
    OR (icd_version = 10 AND icd_code LIKE 'I26%')
),
qt_drugs AS (
  SELECT * FROM UNNEST([
    'amiodarone', 'sotalol', 'quinidine', 'disopyramide', 'dofetilide', 'dronedarone', 
    'ibutilide', 'procainamide', 'arsenic trioxide', 'chlorpromazine', 'clozapine', 
    'haloperidol', 'iloperidone', 'pimozide', 'thioridazine', 'ziprasidone', 
    'citalopram', 'escitalopram', 'fluoxetine'
  ]) AS drug
),
bleed_drugs AS (
  SELECT * FROM UNNEST([
    'warfarin', 'heparin', 'enoxaparin', 'dabigatran', 'rivaroxaban', 'apixaban', 
    'edoxaban', 'aspirin', 'clopidogrel', 'prasugrel', 'ticagrelor', 'dipyridamole', 
    'ibuprofen', 'naproxen', 'diclofenac'
  ]) AS drug
),
cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN pe_admissions pa
    ON a.hadm_id = pa.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 74 AND 84
),
medications AS (
  SELECT 
    c.hadm_id,
    e.medication,
    LOWER(e.medication) AS medication_lower
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.hadm_id = e.hadm_id
  WHERE e.charttime 
    BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
),
hadm_metrics AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COUNT(DISTINCT m.medication) AS medication_complexity,
    MAX(IF(qt.drug IS NOT NULL, 1, 0)) AS qt_drug_flag,
    MAX(IF(bleed.drug IS NOT NULL, 1, 0)) AS bleed_drug_flag,
    MAX(IF(i.stay_id IS NOT NULL, 1, 0)) AS icu_within_24h,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days
  FROM cohort c
  LEFT JOIN medications m
    ON c.hadm_id = m.hadm_id
  LEFT JOIN qt_drugs qt
    ON m.medication_lower LIKE CONCAT('%', qt.drug, '%')
  LEFT JOIN bleed_drugs bleed
    ON m.medication_lower LIKE CONCAT('%', bleed.drug, '%')
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.hadm_id = i.hadm_id
    AND i.intime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
  HAVING COUNT(DISTINCT m.medication) > 0  -- Exclude admissions without medications
),
complexity_cutoff AS (
  SELECT 
    APPROX_QUANTILES(medication_complexity, 100)[OFFSET(75)] AS p75_complexity
  FROM hadm_metrics
),
hadm_metrics_with_top AS (
  SELECT 
    hm.*,
    IF(hm.medication_complexity >= (SELECT p75_complexity FROM complexity_cutoff), 1, 0) AS in_top_quartile
  FROM hadm_metrics hm
),
top_quartile_metrics AS (
  SELECT
    AVG(los_days) AS avg_los_top_quartile,
    AVG(hospital_expire_flag) * 100 AS mortality_rate_top_quartile
  FROM hadm_metrics_with_top
  WHERE in_top_quartile = 1
),
entire_cohort AS (
  SELECT
    'Entire cohort' AS group_name,
    COUNT(*) AS n_patients,
    MIN(medication_complexity) AS min_complexity,
    MAX(medication_complexity) AS max_complexity,
    AVG(medication_complexity) AS avg_complexity,
    STDDEV(medication_complexity) AS std_complexity,
    APPROX_QUANTILES(medication_complexity, 100)[OFFSET(25)] AS p25_complexity,
    APPROX_QUANTILES(medication_complexity, 100)[OFFSET(50)] AS p50_complexity,
    APPROX_QUANTILES(medication_complexity, 100)[OFFSET(75)] AS p75_complexity,
    AVG(qt_drug_flag) * 100 AS qt_prevalence,
    AVG(bleed_drug_flag) * 100 AS bleed_prevalence,
    (SELECT avg_los_top_quartile FROM top_quartile_metrics) AS avg_los_top_quartile,
    (SELECT mortality_rate_top_quartile FROM top_quartile_metrics) AS mortality_rate_top_quartile
  FROM hadm_metrics_with_top
),
icu_groups AS (
  SELECT
    IF(icu_within_24h = 1, 'ICU within 24h', 'Non-ICU') AS group_name,
    COUNT(*) AS n_patients,
    MIN(medication_complexity) AS min_complexity,
    MAX(medication_complexity) AS max_complexity,
    AVG(medication_complexity) AS avg_complexity,
    STDDEV(medication_complexity) AS std_complexity,
    APPROX_QUANTILES(medication_complexity, 100)[OFFSET(25)] AS p25_complexity,
    APPROX_QUANTILES(medication_complexity, 100)[OFFSET(50)] AS p50_complexity,
    APPROX_QUANTILES(medication_complexity, 100)[OFFSET(75)] AS p75_complexity,
    AVG(qt_drug_flag) * 100 AS qt_prevalence,
    AVG(bleed_drug_flag) * 100 AS bleed_prevalence,
    NULL AS avg_los_top_quartile,  -- Not required for ICU groups
    NULL AS mortality_rate_top_quartile
  FROM hadm_metrics_with_top
  GROUP BY icu_within_24h
)
SELECT * FROM entire_cohort
UNION ALL
SELECT * FROM icu_groups;