WITH hs_trop_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%troponin t%'
),

patient_cohort AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 42 AND 52
),

first_hs_trop AS (
  SELECT
    le.subject_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.subject_id ORDER BY le.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN hs_trop_items hi
      ON le.itemid = hi.itemid
  WHERE
    le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
    AND le.subject_id IN (SELECT subject_id FROM patient_cohort)
)

SELECT
  CASE
    WHEN fh.valuenum < 0.014 THEN 'Normal (<0.014)'
    WHEN fh.valuenum >= 0.014
         AND fh.valuenum < 0.04 THEN 'Borderline (0.014–<0.04)'
    WHEN fh.valuenum >= 0.04 THEN 'Myocardial Injury (≥0.04)'
    ELSE 'Uncategorized'
  END AS troponin_category,
  COUNT(DISTINCT fh.subject_id) AS patient_count
FROM
  first_hs_trop fh
WHERE
  fh.rn = 1
GROUP BY
  troponin_category
ORDER BY
  troponin_category;