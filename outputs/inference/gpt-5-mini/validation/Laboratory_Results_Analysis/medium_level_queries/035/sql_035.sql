WITH troponin_t_items AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE REGEXP_CONTAINS(LOWER(label), r'troponin[\s\-_]*t')
),

initial_troponin AS (
  -- earliest troponin T lab during the admission
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    l.valueuom,
    l.flag,
    l.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN troponin_t_items d ON l.itemid = d.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON l.hadm_id = a.hadm_id
   AND l.charttime >= a.admittime
   AND l.charttime <= a.dischtime
),

initial_troponin_first AS (
  SELECT subject_id, hadm_id, charttime, valuenum, valueuom, flag, ref_range_upper
  FROM initial_troponin
  WHERE rn = 1
),

elevated_initial_troponin AS (
  -- heuristic: elevated if flagged high, or numeric > ref_range_upper, or numeric > 0.01 as a fallback
  SELECT hadm_id, subject_id, charttime, valuenum, valueuom, flag, ref_range_upper
  FROM initial_troponin_first
  WHERE valuenum IS NOT NULL
    AND (
      flag = 'H'
      OR (ref_range_upper IS NOT NULL AND valuenum > ref_range_upper)
      OR valuenum > 0.01
    )
),

acs_admissions AS (
  -- admissions with diagnoses matching ACS / MI / unstable angina terms
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
   AND di.icd_version = d.icd_version
  WHERE (
    (d.long_title IS NOT NULL AND (
       LOWER(d.long_title) LIKE '%myocardial%'
    OR LOWER(d.long_title) LIKE '%acute coronary syndrome%'
    OR LOWER(d.long_title) LIKE '%unstable angina%'
    ))
  )
),

final_cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN elevated_initial_troponin t
    ON a.hadm_id = t.hadm_id
  JOIN acs_admissions acs
    ON a.hadm_id = acs.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
)

SELECT
  COUNT(*) AS n_admissions,
  COUNT(DISTINCT subject_id) AS n_patients,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  SUM(hospital_expire_flag) AS n_in_hospital_deaths,
  ROUND(100.0 * SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)), 2) AS in_hospital_mortality_percent
FROM final_cohort;