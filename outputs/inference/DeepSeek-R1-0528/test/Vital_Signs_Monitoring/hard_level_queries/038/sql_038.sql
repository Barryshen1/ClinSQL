WITH cohort AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los AS icu_los,
    p.gender,
    DATETIME_DIFF(ie.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age AS age,
    adm.hospital_expire_flag AS mortality
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  WHERE p.gender = 'F'
    AND DATETIME_DIFF(ie.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age BETWEEN 63 AND 73
),

status_epi AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code = '3453') OR
    (icd_version = 10 AND icd_code LIKE 'G41%')
),

cohort_flag AS (
  SELECT
    c.*,
    CASE WHEN s.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS status_epi_flag
  FROM cohort c
  LEFT JOIN status_epi s
    ON c.hadm_id = s.hadm_id
),

vitals AS (
  SELECT
    ce.stay_id,
    ce.charttime,
    MAX(CASE WHEN ce.itemid = 220045 THEN ce.valuenum END) AS hr,
    MAX(CASE WHEN ce.itemid IN (220050, 220179) THEN ce.valuenum END) AS sbp,
    MAX(CASE WHEN ce.itemid = 220210 THEN ce.valuenum END) AS rr,
    MAX(CASE WHEN ce.itemid = 223761 THEN ce.valuenum 
             WHEN ce.itemid = 223762 THEN (ce.valuenum - 32) * 5/9 
        END) AS temp_c,
    MAX(CASE WHEN ce.itemid = 220277 THEN ce.valuenum END) AS spo2,
    MAX(CASE WHEN ce.itemid IN (220052, 220181) THEN ce.valuenum END) AS map
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort_flag cf
    ON ce.stay_id = cf.stay_id
  WHERE ce.charttime BETWEEN cf.intime AND DATETIME_ADD(cf.intime, INTERVAL 72 HOUR)
    AND ce.itemid IN (220045, 220050, 220179, 220210, 223761, 223762, 220277, 220052, 220181)
    AND ce.valuenum IS NOT NULL
  GROUP BY stay_id, charttime
),

vitals_vii AS (
  SELECT
    stay_id,
    charttime,
    hr,
    sbp,
    rr,
    temp_c,
    spo2,
    map,
    -- Calculate VII components
    CASE
      WHEN hr < 40 OR hr > 140 THEN 4
      WHEN (hr >= 40 AND hr <= 50) OR (hr > 110 AND hr <= 140) THEN 3
      WHEN (hr > 50 AND hr <= 100) OR (hr > 100 AND hr <= 110) THEN 0
      ELSE NULL
    END AS hr_points,
    CASE
      WHEN sbp < 70 THEN 4
      WHEN sbp >= 70 AND sbp < 80 THEN 3
      WHEN sbp >= 80 AND sbp < 100 THEN 2
      WHEN sbp >= 100 AND sbp <= 200 THEN 0
      WHEN sbp > 200 THEN 4
      ELSE NULL
    END AS sbp_points,
    CASE
      WHEN rr < 6 THEN 4
      WHEN rr >= 6 AND rr < 12 THEN 1
      WHEN rr >= 12 AND rr < 24 THEN 0
      WHEN rr >= 24 AND rr < 50 THEN 1
      WHEN rr >= 50 THEN 4
      ELSE NULL
    END AS rr_points,
    CASE
      WHEN temp_c < 35 THEN 4
      WHEN temp_c >= 35 AND temp_c <= 38.5 THEN 0
      WHEN temp_c > 38.5 THEN 1
      ELSE NULL
    END AS temp_points,
    CASE
      WHEN spo2 < 75 THEN 4
      WHEN spo2 >= 75 AND spo2 < 85 THEN 3
      WHEN spo2 >= 85 AND spo2 < 90 THEN 1
      WHEN spo2 >= 90 THEN 0
      ELSE NULL
    END AS spo2_points
  FROM vitals
),

vitals_agg AS (
  SELECT
    stay_id,
    AVG(COALESCE(hr_points,0) + COALESCE(sbp_points,0) + COALESCE(rr_points,0) + COALESCE(temp_points,0) + COALESCE(spo2_points,0)) AS mean_vii,
    AVG(CASE WHEN hr > 100 THEN 1 ELSE 0 END) AS tachycardia_burden,
    AVG(CASE WHEN map < 65 THEN 1 ELSE 0 END) AS map_burden
  FROM vitals_vii
  WHERE hr IS NOT NULL OR map IS NOT NULL  -- Ensure at least one vital exists
  GROUP BY stay_id
),

patient_metrics AS (
  SELECT
    cf.stay_id,
    cf.status_epi_flag,
    cf.icu_los,
    cf.mortality,
    va.mean_vii,
    va.tachycardia_burden,
    va.map_burden
  FROM cohort_flag cf
  LEFT JOIN vitals_agg va
    ON cf.stay_id = va.stay_id
  WHERE va.stay_id IS NOT NULL  -- Exclude patients with no vitals
)

SELECT
  status_epi_flag,
  COUNT(*) AS n_patients,
  AVG(mean_vii) AS mean_vii,
  APPROX_QUANTILES(mean_vii, 100)[OFFSET(25)] AS vii_p25,
  APPROX_QUANTILES(mean_vii, 100)[OFFSET(50)] AS vii_p50,
  APPROX_QUANTILES(mean_vii, 100)[OFFSET(75)] AS vii_p75,
  APPROX_QUANTILES(mean_vii, 100)[OFFSET(90)] AS vii_p90,
  AVG(tachycardia_burden) AS mean_tachycardia_burden,
  APPROX_QUANTILES(tachycardia_burden, 100)[OFFSET(25)] AS tachycardia_burden_p25,
  APPROX_QUANTILES(tachycardia_burden, 100)[OFFSET(50)] AS tachycardia_burden_p50,
  APPROX_QUANTILES(tachycardia_burden, 100)[OFFSET(75)] AS tachycardia_burden_p75,
  APPROX_QUANTILES(tachycardia_burden, 100)[OFFSET(90)] AS tachycardia_burden_p90,
  AVG(map_burden) AS mean_map_burden,
  APPROX_QUANTILES(map_burden, 100)[OFFSET(25)] AS map_burden_p25,
  APPROX_QUANTILES(map_burden, 100)[OFFSET(50)] AS map_burden_p50,
  APPROX_QUANTILES(map_burden, 100)[OFFSET(75)] AS map_burden_p75,
  APPROX_QUANTILES(map_burden, 100)[OFFSET(90)] AS map_burden_p90,
  AVG(icu_los) AS mean_icu_los,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(25)] AS icu_los_p25,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(50)] AS icu_los_p50,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(75)] AS icu_los_p75,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(90)] AS icu_los_p90,
  AVG(mortality) AS mortality_rate
FROM patient_metrics
GROUP BY status_epi_flag;