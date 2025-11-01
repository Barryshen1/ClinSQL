WITH
-- Get female patients aged 41-51 with their admission IDs
female_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year_group,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 41 AND 51
),

-- Get their ICU stays
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime AS icu_intime,
    s.outtime AS icu_outtime,
    s.first_careunit,
    s.last_careunit,
    s.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    female_patients p ON s.subject_id = p.subject_id AND s.hadm_id = p.hadm_id
),

-- Get respiratory rate measurements in first 48 hours
rr_measurements AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS rr_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  JOIN
    icu_stays s ON ce.subject_id = s.subject_id AND ce.stay_id = s.stay_id
  WHERE
    di.label = 'Respiratory Rate'
    AND ce.charttime BETWEEN s.icu_intime AND DATETIME_ADD(s.icu_intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
),

-- Calculate average RR per stay in first 48 hours
avg_rr_per_stay AS (
  SELECT
    subject_id,
    stay_id,
    AVG(rr_value) AS avg_rr,
    COUNT(rr_value) AS rr_count
  FROM
    rr_measurements
  GROUP BY
    subject_id, stay_id
  HAVING
    COUNT(rr_value) >= 1  -- At least one RR measurement
),

-- Categorize patients by RR ranges
rr_categories AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    s.stay_id,
    CASE
      WHEN a.avg_rr < 12 THEN 'RR <12'
      WHEN a.avg_rr BETWEEN 12 AND 20 THEN 'RR 12-20'
      WHEN a.avg_rr BETWEEN 21 AND 29 THEN 'RR 21-29'
      WHEN a.avg_rr >= 30 THEN 'RR ≥30'
      ELSE 'Unknown RR'
    END AS rr_category,
    a.avg_rr
  FROM
    female_patients p
  JOIN
    icu_stays s ON p.subject_id = s.subject_id AND p.hadm_id = s.hadm_id
  JOIN
    avg_rr_per_stay a ON p.subject_id = a.subject_id AND s.stay_id = a.stay_id
),

-- Identify stroke patients
stroke_patients AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    di.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    -- ICD-9 codes for stroke: 430-438
    (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '438')
    OR
    -- ICD-10 codes for stroke: I60-I69
    (d.icd_version = 10 AND d.icd_code BETWEEN 'I60' AND 'I69')
)

-- Final analysis: Count patients by RR category and stroke status
SELECT
  r.rr_category,
  COUNT(DISTINCT r.subject_id) AS total_patients,
  COUNT(DISTINCT s.subject_id) AS stroke_patients,
  ROUND(COUNT(DISTINCT s.subject_id) / COUNT(DISTINCT r.subject_id) * 100, 2) AS stroke_rate_percentage
FROM
  rr_categories r
LEFT JOIN
  stroke_patients s ON r.subject_id = s.subject_id AND r.hadm_id = s.hadm_id
GROUP BY
  r.rr_category
ORDER BY
  CASE r.rr_category
    WHEN 'RR <12' THEN 1
    WHEN 'RR 12-20' THEN 2
    WHEN 'RR 21-29' THEN 3
    WHEN 'RR ≥30' THEN 4
    ELSE 5
  END;