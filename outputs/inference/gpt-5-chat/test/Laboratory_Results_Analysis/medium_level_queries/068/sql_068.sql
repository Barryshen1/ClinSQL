WITH troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
    AND LOWER(fluid) = 'blood'
    AND LOWER(category) = 'chemistry'
),
troponin_labs AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    le.charttime,
    le.valuenum,
    le.valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_items ti
    ON le.itemid = ti.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON le.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 42 AND 52
    AND le.valuenum IS NOT NULL
    AND LOWER(le.valueuom) = 'ng/ml'
),
first_trop AS (
  SELECT
    subject_id,
    valuenum,
    CASE
      WHEN valuenum < 0.014 THEN 'Normal (<0.014 ng/mL)'
      WHEN valuenum >= 0.014 AND valuenum < 0.04 THEN 'Borderline (0.014–<0.04 ng/mL)'
      WHEN valuenum >= 0.04 THEN 'Myocardial Injury (≥0.04 ng/mL)'
      ELSE 'Unknown'
    END AS category
  FROM (
    SELECT
      subject_id,
      valuenum,
      charttime,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY charttime) AS rn
    FROM troponin_labs
  )
  WHERE rn = 1
)
SELECT category, COUNT(DISTINCT subject_id) AS patient_count
FROM first_trop
GROUP BY category
ORDER BY category;