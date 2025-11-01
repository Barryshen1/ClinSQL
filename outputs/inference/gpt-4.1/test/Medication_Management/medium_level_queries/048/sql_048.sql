WITH
-- 1. Get female patients aged 65-75
female_65_75 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 65 AND 75
),

-- 2. Get admissions for these patients with LOS >= 96h
admissions_96h AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN female_65_75 p ON a.subject_id = p.subject_id
  WHERE TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 96
),

-- 3. Get admissions with diabetes and heart failure
admissions_diab_hf AS (
  SELECT hadm_id
  FROM (
    SELECT hadm_id,
      MAX(CASE WHEN
        ( (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250') )
          OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E0[89]|^E1[0-3]') )
        ) THEN 1 ELSE 0 END) AS has_diabetes,
      MAX(CASE WHEN
        ( (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428') )
          OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50') )
        ) THEN 1 ELSE 0 END) AS has_hf
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
  )
  WHERE has_diabetes = 1 AND has_hf = 1
),

-- 4. Final cohort: admissions with all criteria
cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM admissions_96h a
  JOIN admissions_diab_hf d ON a.hadm_id = d.hadm_id
),

-- 5. Insulin mapping: classify insulin types from emar_detail
insulin_map AS (
  SELECT
    ed.subject_id, e.hadm_id, ed.emar_id, e.charttime,
    CASE
      WHEN LOWER(ed.product_description) LIKE '%glargine%' OR LOWER(ed.product_description) LIKE '%detemir%' OR LOWER(ed.product_description) LIKE '%degludec%' OR LOWER(ed.product_description) LIKE '%nph%' THEN 'basal'
      WHEN LOWER(ed.product_description) LIKE '%regular%' OR LOWER(ed.product_description) LIKE '%lispro%' OR LOWER(ed.product_description) LIKE '%aspart%' OR LOWER(ed.product_description) LIKE '%glulisine%' THEN 'bolus'
      ELSE NULL
    END AS insulin_type,
    CASE
      WHEN LOWER(e.event_txt) LIKE '%sliding%' OR LOWER(ed.route) LIKE '%sliding%' THEN 'sliding_scale'
      ELSE NULL
    END AS sliding_scale_flag
  FROM `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
  JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON ed.subject_id = e.subject_id AND ed.emar_id = e.emar_id AND ed.emar_seq = e.emar_seq
  WHERE LOWER(ed.product_description) LIKE '%insulin%'
),

-- 6. For each admission, determine regimen in first 48h and final 48h
regimen_by_window AS (
  SELECT
    c.hadm_id,
    -- First 48h
    MAX(CASE WHEN im.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
      THEN CASE
        WHEN im.sliding_scale_flag = 'sliding_scale' THEN 'sliding_scale'
        WHEN im.insulin_type = 'basal' THEN 'basal'
        WHEN im.insulin_type = 'bolus' THEN 'bolus'
        ELSE NULL
      END
    END) AS first_48h_regimen,
    -- Final 48h
    MAX(CASE WHEN im.charttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
      THEN CASE
        WHEN im.sliding_scale_flag = 'sliding_scale' THEN 'sliding_scale'
        WHEN im.insulin_type = 'basal' THEN 'basal'
        WHEN im.insulin_type = 'bolus' THEN 'bolus'
        ELSE NULL
      END
    END) AS final_48h_regimen,
    -- Basal–bolus: if both basal and bolus in window
    STRING_AGG(DISTINCT CASE WHEN im.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR) THEN im.insulin_type END, ',') AS first_48h_types,
    STRING_AGG(DISTINCT CASE WHEN im.charttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime THEN im.insulin_type END, ',') AS final_48h_types
  FROM cohort c
  LEFT JOIN insulin_map im ON c.hadm_id = im.hadm_id
  GROUP BY c.hadm_id
),

-- 7. Classify basal–bolus if both types present
regimen_final AS (
  SELECT
    hadm_id,
    CASE
      WHEN ARRAY_LENGTH(ARRAY(
        SELECT DISTINCT insulin_type FROM UNNEST(SPLIT(first_48h_types, ',')) AS insulin_type WHERE insulin_type IN ('basal','bolus')
      )) = 2 THEN 'basal_bolus'
      ELSE first_48h_regimen
    END AS first_48h_regimen,
    CASE
      WHEN ARRAY_LENGTH(ARRAY(
        SELECT DISTINCT insulin_type FROM UNNEST(SPLIT(final_48h_types, ',')) AS insulin_type WHERE insulin_type IN ('basal','bolus')
      )) = 2 THEN 'basal_bolus'
      ELSE final_48h_regimen
    END AS final_48h_regimen
  FROM regimen_by_window
),

-- 8. Aggregate: % of patients per regimen per window, and transitions
counts AS (
  SELECT
    first_48h_regimen,
    final_48h_regimen,
    COUNT(*) AS n_admissions
  FROM regimen_final
  GROUP BY first_48h_regimen, final_48h_regimen
),

totals AS (
  SELECT COUNT(*) AS total_admissions FROM regimen_final
)

SELECT
  r.first_48h_regimen AS regimen,
  'first_48h' AS time_window,
  ROUND(100 * SUM(CASE WHEN r.first_48h_regimen IS NOT NULL THEN 1 ELSE 0 END) / t.total_admissions, 1) AS pct_patients
FROM regimen_final r, totals t
GROUP BY regimen

UNION ALL

SELECT
  r.final_48h_regimen AS regimen,
  'final_48h' AS time_window,
  ROUND(100 * SUM(CASE WHEN r.final_48h_regimen IS NOT NULL THEN 1 ELSE 0 END) / t.total_admissions, 1) AS pct_patients
FROM regimen_final r, totals t
GROUP BY regimen

UNION ALL

SELECT
  CONCAT(r.first_48h_regimen, '→', r.final_48h_regimen) AS regimen_transition,
  'early→discharge' AS time_window,
  ROUND(100 * COUNT(*) / t.total_admissions, 1) AS pct_patients
FROM regimen_final r, totals t
WHERE r.first_48h_regimen IS NOT NULL AND r.final_48h_regimen IS NOT NULL AND r.first_48h_regimen != r.final_48h_regimen
GROUP BY regimen_transition
ORDER BY time_window, regimen;