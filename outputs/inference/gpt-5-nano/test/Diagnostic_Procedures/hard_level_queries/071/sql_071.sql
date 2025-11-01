WITH ICH_ADMISSIONS AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 50 AND 60
    AND (
      (di.icd_version = 10 AND (
         di.icd_code LIKE 'I60%' OR
         di.icd_code LIKE 'I61%' OR
         di.icd_code LIKE 'I62%'
      ))
      OR
      (di.icd_version = 9 AND (di.icd_code BETWEEN '430' AND '432'))
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
      WHERE ic.hadm_id = a.hadm_id
    )
),

ICH_ICU_STAYS AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime
  FROM ICH_ADMISSIONS AS a
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON a.hadm_id = ic.hadm_id
),

BURDEN AS (
  SELECT
    s.hadm_id,
    s.stay_id,
    COUNT(*) AS burden
  FROM ICH_ICU_STAYS AS s
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON s.subject_id = pe.subject_id
   AND s.hadm_id = pe.hadm_id
   AND s.stay_id = pe.stay_id
   AND pe.starttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
  GROUP BY s.hadm_id, s.stay_id
),

-- Compute quantiles for burden. Cast to FLOAT64 to ensure numeric input.
BURDEN_QUANT AS (
  SELECT APPROX_QUANTILES(CAST(burden AS FLOAT64), 100) AS quantiles
  FROM BURDEN
),

-- Subset: female ICH, age 50-60 ICU subset: hospital LOS and in-hospital mortality
LOS_SUBSET AS (
  SELECT
    MEDIAN(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 3600.0) AS subset_hosp_los_hours,
    SAFE_DIVIDE(
      SUM(CASE WHEN a.hospital_expire_flag = 1 OR a.deathtime IS NOT NULL THEN 1 ELSE 0 END),
      COUNT(*) ) AS subset_in_hosp_mortality_rate
  FROM ICH_ADMISSIONS AS a
  WHERE EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
      WHERE ic.hadm_id = a.hadm_id
  )
),

-- General ICU: hospital LOS and in-hospital mortality for all ICU patients
LOS_ALL_ICU AS (
  SELECT
    MEDIAN(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 3600.0) AS allicu_median_los_hours,
    SAFE_DIVIDE(
      SUM(CASE WHEN a.hospital_expire_flag = 1 OR a.deathtime IS NOT NULL THEN 1 ELSE 0 END),
      COUNT(*) ) AS allicu_mortality_rate
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON ic.hadm_id = a.hadm_id
)

SELECT
  -- Burden percentiles for the ICH female 50-60 ICU cohort
  b.quantiles[OFFSET(25)] AS burden_p25,
  b.quantiles[OFFSET(50)] AS burden_p50,
  b.quantiles[OFFSET(90)] AS burden_p90,
  b.quantiles[OFFSET(100)] AS burden_max,
  -- Subset results
  ls.subset_hosp_los_hours AS subset_hosp_los_median_hours,
  ls.subset_in_hosp_mortality_rate AS subset_in_hosp_mortality_rate,
  -- General ICU results
  li.allicu_median_los_hours AS allicu_hosp_los_median_hours,
  li.allicu_mortality_rate AS allicu_in_hosp_mortality_rate
FROM BURDEN_QUANT AS b
CROSS JOIN LOS_SUBSET AS ls
CROSS JOIN LOS_ALL_ICU AS li;