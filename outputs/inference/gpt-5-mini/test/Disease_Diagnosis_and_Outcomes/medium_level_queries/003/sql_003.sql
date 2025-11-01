WITH
patients_male_44_54 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 44 AND 54
),

-- Identify stroke admissions and exclude those with both types
hadm_stroke_flags AS (
  SELECT
    d.hadm_id,
    MAX(CASE
          WHEN (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, '^(433|434|436)'))
               OR (d.icd_version = 10 AND REGEXP_CONTAINS(UPPER(d.icd_code), '^I63'))
          THEN 1 ELSE 0 END) AS ischemic_flag,
    MAX(CASE
          WHEN (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, '^(430|431|432)'))
               OR (d.icd_version = 10 AND REGEXP_CONTAINS(UPPER(d.icd_code), '^I6[0-2]'))
          THEN 1 ELSE 0 END) AS hemorr_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN patients_male_44_54 p ON d.subject_id = p.subject_id
  GROUP BY d.hadm_id
),

-- Select admissions that are exclusively ischemic OR exclusively hemorrhagic
cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.admission_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN hadm_stroke_flags s ON a.hadm_id = s.hadm_id
  WHERE (s.ischemic_flag = 1 AND s.hemorr_flag = 0)
     OR (s.hemorr_flag = 1 AND s.ischemic_flag = 0)
),

-- Label the stroke type per admission
cohort_with_type AS (
  SELECT
    c.*,
    CASE
      WHEN s.ischemic_flag = 1 THEN 'ischemic'
      WHEN s.hemorr_flag = 1 THEN 'hemorrhagic'
      ELSE 'other' END AS stroke_type
  FROM cohort_admissions c
  JOIN hadm_stroke_flags s USING (hadm_id)
),

-- Compute LOS in days (fractional)
cohort_with_los AS (
  SELECT
    *,
    SAFE_DIVIDE(TIMESTAMP_DIFF(dischtime, admittime, SECOND), 86400.0) AS los_days,
    CASE WHEN SAFE_DIVIDE(TIMESTAMP_DIFF(dischtime, admittime, SECOND), 86400.0) <= 5 THEN '<=5' ELSE '>5' END AS los_strata
  FROM cohort_with_type
),

-- Compute comorbidity count = number of distinct diagnosis codes excluding the stroke codes
hadm_comorbidity_count AS (
  SELECT
    d.hadm_id,
    COUNT(DISTINCT d.icd_code) -
      COUNT(DISTINCT CASE
        WHEN (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, '^(433|434|436|430|431|432)'))
          OR (d.icd_version = 10 AND REGEXP_CONTAINS(UPPER(d.icd_code), '^I6[0-3]')) THEN d.icd_code
        ELSE NULL END) AS non_stroke_dx_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN cohort_with_type c ON d.hadm_id = c.hadm_id
  GROUP BY d.hadm_id
),

-- Map comorbidity count to levels; thresholds chosen pragmatically
hadm_comorbidity_level AS (
  SELECT
    hadm_id,
    CASE
      WHEN non_stroke_dx_count IS NULL THEN 'low'
      WHEN non_stroke_dx_count <= 2 THEN 'low'
      WHEN non_stroke_dx_count BETWEEN 3 AND 5 THEN 'med'
      ELSE 'high'
    END AS comorbidity_level
  FROM hadm_comorbidity_count
),

-- Detect ICU-based interventions via pattern matching in ICU tables.
-- Mechanical ventilation: look for 'vent' in item labels/values/descriptions.
mech_vent_hadm AS (
  SELECT DISTINCT hadm_id, 1 AS mech_vent FROM (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di USING(itemid)
    WHERE hadm_id IS NOT NULL
      AND (
        LOWER(CAST(di.label AS STRING)) LIKE '%vent%' OR LOWER(CAST(ce.value AS STRING)) LIKE '%vent%' OR LOWER(CAST(ce.value AS STRING)) LIKE '%ventilat%'
      )
    UNION DISTINCT
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di USING(itemid)
    WHERE hadm_id IS NOT NULL
      AND (
        LOWER(CAST(di.label AS STRING)) LIKE '%vent%' OR LOWER(CAST(pe.value AS STRING)) LIKE '%vent%' OR LOWER(CAST(pe.ordercategoryname AS STRING)) LIKE '%vent%'
      )
    UNION DISTINCT
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di USING(itemid)
    WHERE hadm_id IS NOT NULL
      AND (
        LOWER(CAST(di.label AS STRING)) LIKE '%vent%' OR LOWER(CAST(ie.ordercategoryname AS STRING)) LIKE '%vent%' OR LOWER(CAST(ie.ordercomponenttypedescription AS STRING)) LIKE '%vent%'
      )
  )
),

-- Vasopressors: search for common vasopressors by name in input/procedure descriptors
vasopressor_hadm AS (
  SELECT DISTINCT hadm_id, 1 AS vasopressor FROM (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di USING(itemid)
    WHERE hadm_id IS NOT NULL
      AND (
        LOWER(CAST(ie.ordercomponenttypedescription AS STRING)) LIKE '%norepineph%' OR LOWER(CAST(ie.ordercomponenttypedescription AS STRING)) LIKE '%epineph%'
        OR LOWER(CAST(ie.ordercomponenttypedescription AS STRING)) LIKE '%vasopressin%' OR LOWER(CAST(ie.ordercomponenttypedescription AS STRING)) LIKE '%phenyleph%'
        OR LOWER(CAST(ie.ordercomponenttypedescription AS STRING)) LIKE '%dopamine%' OR LOWER(CAST(di.label AS STRING)) LIKE '%norepineph%'
        OR LOWER(CAST(di.label AS STRING)) LIKE '%vasopressin%' OR LOWER(CAST(ie.ordercategoryname AS STRING)) LIKE '%norepineph%'
      )
    UNION DISTINCT
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di USING(itemid)
    WHERE hadm_id IS NOT NULL
      AND (
        LOWER(CAST(pe.value AS STRING)) LIKE '%norepineph%' OR LOWER(CAST(pe.value AS STRING)) LIKE '%epineph%' OR LOWER(CAST(pe.value AS STRING)) LIKE '%vasopressin%'
        OR LOWER(CAST(di.label AS STRING)) LIKE '%norepineph%' OR LOWER(CAST(di.label AS STRING)) LIKE '%vasopressin%'
      )
    UNION DISTINCT
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di USING(itemid)
    WHERE hadm_id IS NOT NULL
      AND (
        LOWER(CAST(ce.value AS STRING)) LIKE '%norepineph%' OR LOWER(CAST(ce.value AS STRING)) LIKE '%epineph%' OR LOWER(CAST(ce.value AS STRING)) LIKE '%vasopressin%'
      )
  )
),

-- RRT (dialysis/CRRT): search for dialysis terms
rrt_hadm AS (
  SELECT DISTINCT hadm_id, 1 AS rrt FROM (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di USING(itemid)
    WHERE hadm_id IS NOT NULL
      AND (
        LOWER(CAST(pe.value AS STRING)) LIKE '%dialysis%' OR LOWER(CAST(pe.value AS STRING)) LIKE '%hemodialysis%' OR LOWER(CAST(pe.value AS STRING)) LIKE '%crrt%'
        OR LOWER(CAST(di.label AS STRING)) LIKE '%dialysis%' OR LOWER(CAST(di.label AS STRING)) LIKE '%hemodialysis%' OR LOWER(CAST(di.label AS STRING)) LIKE '%crrt%'
      )
    UNION DISTINCT
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di USING(itemid)
    WHERE hadm_id IS NOT NULL
      AND (
        LOWER(CAST(ie.ordercomponenttypedescription AS STRING)) LIKE '%dialysis%' OR LOWER(CAST(ie.ordercomponenttypedescription AS STRING)) LIKE '%crrt%'
        OR LOWER(CAST(ie.ordercategoryname AS STRING)) LIKE '%dialysis%' OR LOWER(CAST(di.label AS STRING)) LIKE '%dialysis%'
      )
    UNION DISTINCT
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di USING(itemid)
    WHERE hadm_id IS NOT NULL
      AND (
        LOWER(CAST(ce.value AS STRING)) LIKE '%dialysis%' OR LOWER(CAST(ce.value AS STRING)) LIKE '%crrt%' OR LOWER(CAST(ce.value AS STRING)) LIKE '%renal replacement%'
      )
  )
),

-- Combine flags per hadm_id
hadm_interventions AS (
  SELECT
    c.hadm_id,
    IFNULL(MAX(mv.mech_vent), 0) AS mech_vent,
    IFNULL(MAX(vp.vasopressor), 0) AS vasopressor,
    IFNULL(MAX(r.rrt), 0) AS rrt
  FROM cohort_with_los c
  LEFT JOIN mech_vent_hadm mv ON c.hadm_id = mv.hadm_id
  LEFT JOIN vasopressor_hadm vp ON c.hadm_id = vp.hadm_id
  LEFT JOIN rrt_hadm r ON c.hadm_id = r.hadm_id
  GROUP BY c.hadm_id
),

-- Assemble final per-admission dataset with comorbidity level and intervention flags
final_admissions AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.stroke_type,
    c.los_days,
    c.los_strata,
    COALESCE(hc.comorbidity_level, 'low') AS comorbidity_level,
    COALESCE(hint.mech_vent, 0) AS mech_vent,
    COALESCE(hint.vasopressor, 0) AS vasopressor,
    COALESCE(hint.rrt, 0) AS rrt
  FROM cohort_with_los c
  LEFT JOIN hadm_comorbidity_level hc ON c.hadm_id = hc.hadm_id
  LEFT JOIN hadm_interventions hint ON c.hadm_id = hint.hadm_id
)

-- Aggregate results by stroke type, LOS strata, comorbidity level
SELECT
  stroke_type,
  los_strata,
  comorbidity_level,
  COUNT(DISTINCT hadm_id) AS n_admissions,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(DISTINCT hadm_id), 2) AS mortality_pct,
  -- approximate median LOS (days) using APPROX_QUANTILES and taking the 50th percentile
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  ROUND(100.0 * SUM(mech_vent) / COUNT(DISTINCT hadm_id), 1) AS pct_mech_vent,
  ROUND(100.0 * SUM(vasopressor) / COUNT(DISTINCT hadm_id), 1) AS pct_vasopressor,
  ROUND(100.0 * SUM(rrt) / COUNT(DISTINCT hadm_id), 1) AS pct_rrt
FROM final_admissions fv
GROUP BY stroke_type, los_strata, comorbidity_level
ORDER BY stroke_type, los_strata, comorbidity_level;