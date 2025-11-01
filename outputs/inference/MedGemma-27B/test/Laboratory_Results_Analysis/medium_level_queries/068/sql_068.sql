WITH Troponin AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    l.value AS troponin_value,
    l.valueuom AS troponin_unit
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
      ON p.subject_id = l.subject_id
  WHERE
    l.itemid = 50178 -- hs-Troponin T
    AND l.valueuom = 'ng/mL'
),
CategorizedTroponin AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    CASE
      WHEN troponin_value < 0.014
      THEN 'Normal (<0.014 ng/mL)'
      WHEN troponin_value >= 0.014 AND troponin_value < 0.04
      THEN 'Borderline (0.014–<0.04)'
      ELSE 'Myocardial Injury (≥0.04)'
    END AS troponin_category
  FROM
    Troponin
)
SELECT
  troponin_category,
  COUNT(subject_id) AS patient_count
FROM
  CategorizedTroponin
WHERE
  gender = 'F'
  AND anchor_age BETWEEN 42 AND 52
GROUP BY
  troponin_category
ORDER BY
  troponin_category;