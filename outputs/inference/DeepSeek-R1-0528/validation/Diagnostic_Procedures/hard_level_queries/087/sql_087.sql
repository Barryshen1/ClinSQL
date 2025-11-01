WITH patient_admissions AS (
  SELECT 
      p.subject_id, 
      p.gender,
      a.hadm_id,
      a.hospital_expire_flag,
      -- Compute age at admission: anchor_age + (admission year - anchor_year)
      p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_adm
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
),

ich_diagnoses AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
      (icd_version = 9 AND icd_code IN ('430', '431', '432')) OR
      (icd_version = 10 AND icd_code IN ('I60', 'I61', 'I62'))
),

ich_cohort_icu AS (
  SELECT 
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      i.outtime,
      i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN patient_admissions pa
      ON i.hadm_id = pa.hadm_id
  INNER JOIN ich_diagnoses icd
      ON i.hadm_id = icd.hadm_id
  WHERE 
      pa.gender = 'F' 
      AND pa.age_adm BETWEEN 56 AND 66
),

lab_counts AS (
  SELECT 
      i.stay_id,
      COUNT(*) AS cnt
  FROM ich_cohort_icu i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON i.hadm_id = l.hadm_id
  WHERE 
      l.charttime >= i.intime
      AND l.charttime < DATETIME_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY i.stay_id
),

micro_counts AS (
  SELECT 
      i.stay_id,
      COUNT(*) AS cnt
  FROM ich_cohort_icu i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` m
      ON i.hadm_id = m.hadm_id
  WHERE 
      m.charttime >= i.intime
      AND m.charttime < DATETIME_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY i.stay_id
),

diagnostic_intensity AS (
  SELECT 
      i.stay_id,
      COALESCE(l.cnt, 0) + COALESCE(m.cnt, 0) AS diag_intensity
  FROM ich_cohort_icu i
  LEFT JOIN lab_counts l ON i.stay_id = l.stay_id
  LEFT JOIN micro_counts m ON i.stay_id = m.stay_id
),

ich_cohort_aggregates AS (
  SELECT 
      APPROX_QUANTILES(di.diag_intensity, 100)[OFFSET(95)] AS diag_intensity_95th,
      APPROX_QUANTILES(i.los, 100)[OFFSET(25)] AS los_q1,
      APPROX_QUANTILES(i.los, 100)[OFFSET(50)] AS los_median,
      APPROX_QUANTILES(i.los, 100)[OFFSET(75)] AS los_q3,
      COUNT(i.stay_id) AS num_icu_stays
  FROM ich_cohort_icu i
  LEFT JOIN diagnostic_intensity di ON i.stay_id = di.stay_id
),

ich_mortality AS (
  SELECT 
      AVG(CAST(pa.hospital_expire_flag AS FLOAT64)) AS mortality_rate,
      COUNT(DISTINCT i.hadm_id) AS num_admissions
  FROM ich_cohort_icu i
  INNER JOIN patient_admissions pa ON i.hadm_id = pa.hadm_id
),

all_icu_aggregates AS (
  SELECT 
      APPROX_QUANTILES(los, 100)[OFFSET(25)] AS los_q1,
      APPROX_QUANTILES(los, 100)[OFFSET(50)] AS los_median,
      APPROX_QUANTILES(los, 100)[OFFSET(75)] AS los_q3,
      COUNT(stay_id) AS num_icu_stays
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

all_icu_mortality AS (
  SELECT 
      AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS mortality_rate,
      COUNT(DISTINCT i.hadm_id) AS num_admissions
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON i.hadm_id = a.hadm_id
)

SELECT 
    'ICH Cohort' AS cohort,
    ica.diag_intensity_95th,
    ica.los_median,
    ica.los_q1,
    ica.los_q3,
    im.mortality_rate,
    ica.num_icu_stays,
    im.num_admissions
FROM ich_cohort_aggregates ica, ich_mortality im

UNION ALL

SELECT 
    'Entire ICU Population' AS cohort,
    NULL AS diag_intensity_95th,
    aica.los_median,
    aica.los_q1,
    aica.los_q3,
    aim.mortality_rate,
    aica.num_icu_stays,
    aim.num_admissions
FROM all_icu_aggregates aica, all_icu_mortality aim;