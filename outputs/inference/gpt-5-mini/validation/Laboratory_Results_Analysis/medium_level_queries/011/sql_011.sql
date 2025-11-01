WITH hs_tnt_items AS (
  -- find lab itemids that look like high-sensitivity Troponin T
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
    AND (LOWER(label) LIKE '%hs%' OR LOWER(label) LIKE '%high%')
),

chest_pain_hadm AS (
  -- admissions for male patients aged 61-71 with a diagnosis whose description includes "chest pain"
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON di.icd_code = dic.icd_code AND di.icd_version = dic.icd_version
  WHERE LOWER(p.gender) IN ('m', 'male')
    AND p.anchor_age BETWEEN 61 AND 71
    AND LOWER(dic.long_title) LIKE '%chest pain%'
),

initial_tnt AS (
  -- earliest hs-TnT per admission (first charttime for matching hs-TnT itemids)
  SELECT
    c.subject_id,
    c.hadm_id,
    le.itemid,
    le.charttime,
    le.valuenum
  FROM chest_pain_hadm c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = c.hadm_id
  JOIN hs_tnt_items i
    ON le.itemid = i.itemid
  WHERE le.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY c.hadm_id ORDER BY le.charttime) = 1
),

categorized AS (
  -- categorize initial hs-TnT using chosen thresholds:
  -- normal: valuenum < 14 ng/L
  -- borderline: 14 <= valuenum <= 52 ng/L
  -- myocardial injury: valuenum > 52 ng/L
  SELECT
    subject_id,
    hadm_id,
    valuenum,
    CASE
      WHEN valuenum < 14 THEN 'normal'
      WHEN valuenum BETWEEN 14 AND 52 THEN 'borderline'
      WHEN valuenum > 52 THEN 'myocardial injury'
      ELSE 'unknown'
    END AS category
  FROM initial_tnt
)

SELECT
  category,
  COUNT(*) AS n,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percent_of_admissions_with_test
FROM categorized
GROUP BY category
ORDER BY CASE category
         WHEN 'normal' THEN 1
         WHEN 'borderline' THEN 2
         WHEN 'myocardial injury' THEN 3
         ELSE 4 END;