WITH pe_cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.hospital_expire_flag,
    icu.stay_id,
    icu.los,
    -- Calculate diagnostic score: distinct lab + micro tests in first 24h
    COUNT(DISTINCT lab.itemid) + COUNT(DISTINCT micro.test_itemid) AS diagnostic_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN (
    SELECT * 
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    QUALIFY ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) = 1
  ) icu
    ON adm.hadm_id = icu.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON adm.hadm_id = lab.hadm_id
    AND adm.subject_id = lab.subject_id
    AND lab.charttime >= icu.intime
    AND lab.charttime < DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` micro
    ON adm.hadm_id = micro.hadm_id
    AND adm.subject_id = micro.subject_id
    AND micro.charttime >= icu.intime
    AND micro.charttime < DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 79 AND 89
    AND (
      (diag.icd_version = 9 AND diag.icd_code IN ('4151', '41511', '41519'))
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I26%')
    )
  GROUP BY adm.subject_id, adm.hadm_id, adm.hospital_expire_flag, icu.stay_id, icu.los
),
general_pop AS (
  SELECT
    adm.hospital_expire_flag,
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY icu.hadm_id ORDER BY icu.intime) = 1
),
pe_agg AS (
  SELECT
    APPROX_QUANTILES(diagnostic_score, 100)[OFFSET(75)] AS diag_75,
    PERCENTILE_CONT(los, 0.5) AS median_los_pe,
    AVG(hospital_expire_flag) AS mortality_pe
  FROM pe_cohort
),
gen_agg AS (
  SELECT
    PERCENTILE_CONT(los, 0.5) AS median_los_gen,
    AVG(hospital_expire_flag) AS mortality_gen
  FROM general_pop
)
SELECT
  'diagnostic_utilization_score_75th_percentile' AS metric,
  diag_75 AS pe_cohort_value,
  NULL AS general_population_value
FROM pe_agg
UNION ALL
SELECT
  'icu_los_median' AS metric,
  median_los_pe,
  median_los_gen
FROM pe_agg, gen_agg
UNION ALL
SELECT
  'in_hospital_mortality_rate' AS metric,
  mortality_pe,
  mortality_gen
FROM pe_agg, gen_agg;