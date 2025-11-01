WITH
-- Identify HFNC itemid (example: 223849 is often used for HFNC in MIMIC-IV)
hfnc_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%High Flow Nasal Cannula%'
),

-- Identify GCS total itemid (example: 198 is often used for GCS total)
gcs_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%GCS Total%'
),

-- Get female patients aged 88-98
female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 88 AND 98
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT s.subject_id, s.hadm_id, s.stay_id, s.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN female_patients p ON s.subject_id = p.subject_id
),

-- Get patients on HFNC
hfnc_patients AS (
  SELECT DISTINCT c.subject_id, c.hadm_id, c.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN hfnc_item h ON c.itemid = h.itemid
  JOIN icu_stays s ON c.subject_id = s.subject_id AND c.hadm_id = s.hadm_id AND c.stay_id = s.stay_id
),

-- Get GCS totals on ICU day 2 or later
gcs_records AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.valuenum AS gcs_total,
    DATE_DIFF(c.charttime, s.intime, DAY) AS icu_day
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN gcs_item g ON c.itemid = g.itemid
  JOIN icu_stays s ON c.subject_id = s.subject_id AND c.hadm_id = s.hadm_id AND c.stay_id = s.stay_id
  JOIN hfnc_patients h ON c.subject_id = h.subject_id AND c.hadm_id = h.hadm_id AND c.stay_id = h.stay_id
  WHERE c.valuenum IS NOT NULL
  AND DATE_DIFF(c.charttime, s.intime, DAY) >= 2
)

-- Calculate median GCS per patient
SELECT
  subject_id,
  hadm_id,
  stay_id,
  PERCENTILE_CONT(gcs_total, 0.5) OVER (PARTITION BY subject_id, hadm_id) AS median_gcs
FROM gcs_records
GROUP BY subject_id, hadm_id, stay_id, gcs_total
ORDER BY subject_id, hadm_id;