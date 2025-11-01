WITH septic_females AS (
  -- Identify septic-shock admissions for females aged 57-67
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.hadm_id = a.hadm_id AND di.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dd.icd_code = di.icd_code AND dd.icd_version = di.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
    AND UPPER(dd.long_title) LIKE '%SEPTIC SHOCK%'
),

icu_hadm AS (
  -- Admissions with an ICU stay
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

ultrasound_counts_by_hadm AS (
  -- Ultrasound-related chart events during ICU stays, per hadm_id (aggregated across ICU stays per admission)
  SELECT ci.hadm_id, COUNT(*) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ci
    ON ce.stay_id = ci.stay_id
  WHERE LOWER(di.label) LIKE '%ultrasound%'
     OR LOWER(di.label) LIKE '%echo%'
  GROUP BY ci.hadm_id
),

admissions_with_los AS (
  -- Admissions from septic_females with LOS computed
  SELECT a.hadm_id,
         a.subject_id,
         DATE(a.admittime) AS adm_date,
         DATE(a.dischtime) AS dis_date,
         DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM septic_females s
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE a.dischtime IS NOT NULL
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
),

expanded AS (
  SELECT
    a.hadm_id,
    CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END AS icu_group,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS los_group,
    COALESCE(uc.ultrasound_count, 0) AS ultrasound_count
  FROM admissions_with_los a
  LEFT JOIN ultrasound_counts_by_hadm uc
    ON a.hadm_id = uc.hadm_id
  LEFT JOIN icu_hadm icu
    ON a.hadm_id = icu.hadm_id
  WHERE los_days BETWEEN 1 AND 7
)

SELECT
  los_group,
  icu_group,
  quantiles[SAFE_OFFSET(1)] AS p25,
  quantiles[SAFE_OFFSET(2)] AS p50,
  quantiles[SAFE_OFFSET(3)] AS p75
FROM (
  SELECT los_group, icu_group, APPROX_QUANTILES(ultrasound_count, 4) AS quantiles
  FROM expanded
  GROUP BY los_group, icu_group
)
ORDER BY los_group, icu_group;