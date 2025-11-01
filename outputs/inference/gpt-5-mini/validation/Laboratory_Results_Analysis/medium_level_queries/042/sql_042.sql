WITH
-- 1) cohort of admissions: female patients aged 84-94 with a diagnosis mentioning "chest pain"
chest_pain_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND LOWER(dd.long_title) LIKE '%chest pain%'
),

-- 2) troponin T itemids (by label)
troponin_t_items AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),

-- 3) first troponin T measurement per admission (earliest charttime; tie-breaker by labevent_id)
first_troponin_per_hadm AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.labevent_id,
    le.charttime,
    SAFE_CAST(le.valuenum AS FLOAT64) AS valuenum,
    le.valueuom,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime, le.labevent_id) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_t_items tti
    ON le.itemid = tti.itemid
  WHERE le.hadm_id IS NOT NULL
),

-- 4) keep only the first troponin per hadm among our chest pain admissions
first_trop_for_cohort AS (
  SELECT f.subject_id, f.hadm_id, f.valuenum, f.valueuom, f.charttime
  FROM first_troponin_per_hadm f
  JOIN chest_pain_admissions c
    ON f.hadm_id = c.hadm_id
  WHERE f.rn = 1
),

-- 5) categorize troponin values
categorized AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    c.charttime,
    c.valuenum,
    c.valueuom,
    CASE
      WHEN c.valuenum IS NULL THEN 'unknown'
      WHEN c.valuenum <= 0.01 THEN 'normal'
      WHEN c.valuenum > 0.01 AND c.valuenum <= 0.04 THEN 'borderline'
      WHEN c.valuenum > 0.04 THEN 'elevated'
      ELSE 'unknown'
    END AS troponin_category,
    a.hospital_expire_flag
  FROM first_trop_for_cohort c
  JOIN chest_pain_admissions a
    ON c.hadm_id = a.hadm_id
)

-- Final aggregation: counts, percentages, and in-hospital mortality by category
SELECT
  troponin_category,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_cohort_with_tropT,
  SUM(hospital_expire_flag) AS deaths_in_hospital,
  ROUND(100.0 * SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)), 2) AS in_hospital_mortality_pct
FROM categorized
GROUP BY troponin_category
ORDER BY
  CASE troponin_category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'elevated' THEN 3
    WHEN 'unknown' THEN 4
    ELSE 5
  END;