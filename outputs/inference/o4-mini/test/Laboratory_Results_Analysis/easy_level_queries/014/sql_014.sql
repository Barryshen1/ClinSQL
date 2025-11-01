WITH hem_items AS (
  -- identify all lab itemids corresponding to hemoglobin measurements
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%hemoglobin%'
),
gi_bleed_admissions AS (
  -- admissions for 45 y/o females with a GI bleeding diagnosis
  SELECT DISTINCT a.subject_id, a.hadm_id, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
  WHERE p.anchor_age = 45
    AND p.gender = 'F'
    AND LOWER(dd.long_title) LIKE '%gastrointestinal hemorrhage%'
),
discharge_hemoglobin AS (
  -- take the hemoglobin measurement closest to discharge time on the discharge date
  SELECT
    g.subject_id,
    g.hadm_id,
    le.valuenum AS discharge_hb
  FROM gi_bleed_admissions AS g
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON g.subject_id = le.subject_id
   AND g.hadm_id    = le.hadm_id
  JOIN hem_items AS hi
    ON le.itemid = hi.itemid
  WHERE DATE(le.charttime) = DATE(g.dischtime)
    AND le.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY g.hadm_id
    ORDER BY le.charttime DESC
  ) = 1
)
SELECT
  -- compute the 75th percentile of discharge-day hemoglobin values
  (APPROX_QUANTILES(discharge_hb, 100))[OFFSET(75)] AS p75_discharge_hb_g_dL
FROM discharge_hemoglobin;