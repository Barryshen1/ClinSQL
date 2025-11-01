WITH male_90_100 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 90 AND 100
),
acs_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN male_90_100 p ON adm.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx ON adm.hadm_id = dx.hadm_id
  WHERE (
    -- ICD-9 ACS codes
    (dx.icd_version = 9 AND LEFT(dx.icd_code,3) IN ('410','411','412','413','414'))
    OR
    -- ICD-10 ACS codes
    (dx.icd_version = 10 AND LEFT(dx.icd_code,3) IN ('I20','I21','I22','I23','I24','I25'))
  )
),
troponin_t_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
index_troponin AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    MIN(le.charttime) AS index_charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_t_items tti ON le.itemid = tti.itemid
  GROUP BY le.subject_id, le.hadm_id
),
troponin_values AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_t_items tti ON le.itemid = tti.itemid
),
acs_with_troponin AS (
  SELECT
    aa.subject_id,
    aa.hadm_id,
    aa.admittime,
    aa.dischtime,
    tv.valuenum AS troponin_t_value
  FROM acs_admissions aa
  JOIN index_troponin it ON aa.subject_id = it.subject_id AND aa.hadm_id = it.hadm_id
  JOIN troponin_values tv
    ON it.subject_id = tv.subject_id
    AND it.hadm_id = tv.hadm_id
    AND it.index_charttime = tv.charttime
  WHERE tv.valuenum IS NOT NULL
),
categorized AS (
  SELECT
    *,
    CASE
      WHEN troponin_t_value <= 0.01 THEN 'Normal'
      WHEN troponin_t_value > 0.01 AND troponin_t_value <= 0.03 THEN 'Borderline'
      WHEN troponin_t_value > 0.03 THEN 'Elevated'
      ELSE 'Unknown'
    END AS troponin_category,
    SAFE_CAST(DATETIME_DIFF(dischtime, admittime, DAY) AS FLOAT64) AS los_days
  FROM acs_with_troponin
)
SELECT
  troponin_category,
  COUNT(*) AS admission_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(los_days), 2) AS mean_los_days
FROM categorized
WHERE troponin_category IN ('Normal','Borderline','Elevated')
GROUP BY troponin_category
ORDER BY troponin_category;