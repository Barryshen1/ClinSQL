WITH hs_troponin_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
    AND (LOWER(label) LIKE '%hs%' OR LOWER(label) LIKE '%high sensitivity%')
),

female_42_52 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 42 AND 52
),

first_hs_troponin AS (
  SELECT
    l.subject_id,
    l.charttime,
    l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN hs_troponin_itemids h ON l.itemid = h.itemid
  INNER JOIN female_42_52 p ON l.subject_id = p.subject_id
  WHERE l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/mL'
),
first_per_patient AS (
  SELECT
    subject_id,
    valuenum AS hs_troponin_t_value
  FROM (
    SELECT
      subject_id,
      valuenum,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY charttime ASC) AS rn
    FROM first_hs_troponin
  )
  WHERE rn = 1
),
categorized AS (
  SELECT
    subject_id,
    hs_troponin_t_value,
    CASE
      WHEN hs_troponin_t_value < 0.014 THEN 'Normal (<0.014 ng/mL)'
      WHEN hs_troponin_t_value >= 0.014 AND hs_troponin_t_value < 0.04 THEN 'Borderline (0.014–<0.04 ng/mL)'
      WHEN hs_troponin_t_value >= 0.04 THEN 'Myocardial Injury (≥0.04 ng/mL)'
      ELSE 'Unknown'
    END AS hs_troponin_t_category
  FROM first_per_patient
)
SELECT
  hs_troponin_t_category,
  COUNT(DISTINCT subject_id) AS patient_count
FROM categorized
WHERE hs_troponin_t_category != 'Unknown'
GROUP BY hs_troponin_t_category
ORDER BY
  CASE hs_troponin_t_category
    WHEN 'Normal (<0.014 ng/mL)' THEN 1
    WHEN 'Borderline (0.014–<0.04 ng/mL)' THEN 2
    WHEN 'Myocardial Injury (≥0.04 ng/mL)' THEN 3
    ELSE 4
  END;