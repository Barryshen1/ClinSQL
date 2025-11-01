WITH cohort AS (
  -- Base cohort: female, age 38-48
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

aki_cohort AS (
  -- Flag AKI admissions
  SELECT 
    c.*,
    CASE WHEN aki_flag.has_aki = 1 THEN TRUE ELSE FALSE END AS has_aki
  FROM cohort c
  LEFT JOIN (
    SELECT DISTINCT 
      di.hadm_id,
      1 AS has_aki
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code 
      AND di.icd_version = d.icd_version
    WHERE 
      d.icd_code LIKE 'N17%'  -- AKI ICD-10 codes
  ) aki_flag
  ON c.hadm_id = aki_flag.hadm_id
  WHERE 
    aki_flag.has_aki = 1  -- Only AKI admissions
),

icu_flag AS (
  -- Flag admissions with any ICU stay
  SELECT 
    ac.*,
    CASE WHEN icu_stays.stay_id IS NOT NULL THEN TRUE ELSE FALSE END AS has_icu
  FROM aki_cohort ac
  LEFT JOIN (
    SELECT DISTINCT 
      subject_id,
      hadm_id,
      stay_id
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu_stays
  ON ac.subject_id = icu_stays.subject_id 
    AND ac.hadm_id = icu_stays.hadm_id
),

los_group AS (
  -- Stratify LOS
  SELECT 
    *,
    CASE 
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4_days'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7_days'
    END AS los_strata
  FROM icu_flag
),

diagnostics_count AS (
  -- Count non-invasive diagnostics per admission
  SELECT 
    lg.hadm_id,
    lg.los_strata,
    lg.has_icu,
    COALESCE(lab_counts.lab_count, 0) + COALESCE(omr_counts.omr_count, 0) AS total_diagnostics
  FROM los_group lg
  LEFT JOIN (
    -- Blood and urine labs (approximate key itemids for AKI-relevant non-invasive labs)
    SELECT 
      le.hadm_id,
      COUNT(DISTINCT le.labevent_id) AS lab_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
    WHERE 
      le.hadm_id IN (SELECT hadm_id FROM los_group)
      AND le.valuenum IS NOT NULL
      AND dli.category IN ('Chemistry', 'Urine')  -- Non-invasive lab categories
      AND le.itemid IN (50006, 50027, 50185, 51221, 51222, 50809, 50810, 50960, 51084, 51156)  -- e.g., Creatinine, BUN, Na, K, Urine protein, etc.
      AND le.priority != 'HIGH'  -- Routine only
    GROUP BY le.hadm_id
  ) lab_counts
  ON lg.hadm_id = lab_counts.hadm_id
  LEFT JOIN (
    -- Non-invasive diagnostics from OMR (e.g., X-ray, ultrasound, ECG)
    SELECT 
      a.hadm_id,
      COUNT(DISTINCT o.seq_num) AS omr_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.omr` o
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON o.subject_id = a.subject_id 
      AND o.chartdate >= DATE(a.admittime) 
      AND o.chartdate <= DATE(a.dischtime)
    WHERE 
      a.hadm_id IN (SELECT hadm_id FROM los_group)
      AND (
        o.result_name LIKE '%X-RAY%' 
        OR o.result_name LIKE '%ULTRASOUND%' 
        OR o.result_name LIKE '%ECG%' 
        OR o.result_name LIKE '%EKG%'
      )  -- Common non-invasive diagnostic orders
      AND o.result_value IS NOT NULL
    GROUP BY a.hadm_id
  ) omr_counts
  ON lg.hadm_id = omr_counts.hadm_id
)

-- Final aggregation: mean, min, max per strata
SELECT 
  los_strata,
  has_icu,
  COUNT(*) AS num_admissions,
  AVG(total_diagnostics) AS mean_diagnostics,
  MIN(total_diagnostics) AS min_diagnostics,
  MAX(total_diagnostics) AS max_diagnostics
FROM diagnostics_count
GROUP BY los_strata, has_icu
ORDER BY los_strata, has_icu;