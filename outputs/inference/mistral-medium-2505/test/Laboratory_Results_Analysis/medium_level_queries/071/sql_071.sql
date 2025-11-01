WITH
-- Get female patients aged 43-53
female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 43 AND 53
),

-- Get admissions with suspected ACS
acs_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR)/24 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE a.subject_id IN (SELECT subject_id FROM female_patients)
    AND (
      -- ICD-9 codes for ACS
      (d.icd_version = 9 AND d.icd_code LIKE '410.%') OR
      (d.icd_version = 9 AND d.icd_code LIKE '411.1') OR
      (d.icd_version = 9 AND d.icd_code LIKE '411.81') OR
      -- ICD-10 codes for ACS
      (d.icd_version = 10 AND d.icd_code LIKE 'I21.%') OR
      (d.icd_version = 10 AND d.icd_code = 'I20.0')
    )
),

-- Get Troponin T lab items
troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%Troponin T%' OR label LIKE '%TnT%'
),

-- Get first Troponin T measurement for each admission
first_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.valuenum,
    l.valueuom,
    l.charttime,
    l.ref_range_upper,
    l.ref_range_lower,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN troponin_items t ON l.itemid = t.itemid
  WHERE l.hadm_id IN (SELECT hadm_id FROM acs_admissions)
  AND l.valuenum IS NOT NULL
),

-- Classify Troponin results
troponin_classification AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN valuenum < ref_range_upper THEN 'Normal'
      WHEN ref_range_lower IS NOT NULL AND valuenum BETWEEN ref_range_lower AND ref_range_upper THEN 'Borderline'
      WHEN valuenum > ref_range_upper THEN 'Elevated'
      ELSE 'Unknown'
    END AS troponin_category
  FROM first_troponin
  WHERE rn = 1
)

-- Final aggregation
SELECT
  t.troponin_category,
  COUNT(DISTINCT t.hadm_id) AS patient_count,
  ROUND(COUNT(DISTINCT t.hadm_id) * 100.0 / SUM(COUNT(DISTINCT t.hadm_id)) OVER(), 2) AS percentage,
  ROUND(AVG(a.los_days), 2) AS avg_los_days
FROM troponin_classification t
JOIN acs_admissions a ON t.hadm_id = a.hadm_id
GROUP BY t.troponin_category
ORDER BY
  CASE t.troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
    ELSE 4
  END;