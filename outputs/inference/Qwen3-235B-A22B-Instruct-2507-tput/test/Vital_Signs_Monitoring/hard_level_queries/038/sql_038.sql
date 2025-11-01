WITH cohort AS (
  SELECT DISTINCT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.los AS icu_los, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON icu.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON icu.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE pat.gender = 'F'
    AND DATE_DIFF(icu.intime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR) + pat.anchor_age BETWEEN 63 AND 73
    AND LOWER(d_diag.long_title) LIKE '%status epilepticus%'
    AND (d_diag.icd_code = '345.3' OR d_diag.icd_code = 'G41.9')
),
vitals_items AS (
  SELECT itemid, LOWER(label) AS label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN ('heart rate', 'mean blood pressure')
),
vitals AS (
  SELECT ce.stay_id, ce.itemid, ce.charttime, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN vitals_items vi ON ce.itemid = vi.itemid
  INNER JOIN cohort co ON ce.stay_id = co.stay_id
  WHERE ce.charttime >= co.intime
    AND ce.charttime <= DATETIME_ADD(co.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
),
burden AS (
  SELECT
    stay_id,
    AVG(CASE WHEN itemid = (SELECT itemid FROM vitals_items WHERE label = 'heart rate') AND valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_burden,
    AVG(CASE WHEN itemid = (SELECT itemid FROM vitals_items WHERE label = 'mean blood pressure') AND valuenum < 65 THEN 1 ELSE 0 END) AS map_low_burden
  FROM vitals
  GROUP BY stay_id
),
summary_stats AS (
  SELECT
    AVG(tachycardia_burden) AS mean_tachycardia_burden,
    APPROX_QUANTILES(tachycardia_burden, 100)[OFFSET(25)] AS tachycardia_p25,
    APPROX_QUANTILES(tachycardia_burden, 100)[OFFSET(50)] AS tachycardia_p50,
    APPROX_QUANTILES(tachycardia_burden, 100)[OFFSET(75)] AS tachycardia_p75,
    APPROX_QUANTILES(tachycardia_burden, 100)[OFFSET(90)] AS tachycardia_p90,
    AVG(map_low_burden) AS mean_map_low_burden,
    APPROX_QUANTILES(map_low_burden, 100)[OFFSET(25)] AS map_low_p25,
    APPROX_QUANTILES(map_low_burden, 100)[OFFSET(50)] AS map_low_p50,
    APPROX_QUANTILES(map_low_burden, 100)[OFFSET(75)] AS map_low_p75,
    APPROX_QUANTILES(map_low_burden, 100)[OFFSET(90)] AS map_low_p90,
    AVG(icu_los) AS mean_icu_los,
    APPROX_QUANTILES(icu_los, 100)[OFFSET(50)] AS icu_los_p50,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM burden b
  INNER JOIN cohort c ON b.stay_id = c.stay_id
)
SELECT
  mean_tachycardia_burden,
  tachycardia_p25,
  tachycardia_p50,
  tachycardia_p75,
  tachycardia_p90,
  mean_map_low_burden,
  map_low_p25,
  map_low_p50,
  map_low_p75,
  map_low_p90,
  mean_icu_los,
  icu_los_p50,
  mortality_rate
FROM summary_stats;