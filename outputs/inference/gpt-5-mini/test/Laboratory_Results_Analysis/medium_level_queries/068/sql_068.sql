WITH female_patients AS (
  -- female patients aged between 42 and 52 inclusive
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 42 AND 52
),

troponin_items AS (
  -- candidate troponin T / hs-troponin items by label text (adjust if you have a specific itemid list)
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE (
      LOWER(label) LIKE '%troponin t%'
      OR LOWER(label) LIKE '%troponin-t%'
      OR (LOWER(label) LIKE '%troponin%' AND (LOWER(label) LIKE '%hs%' OR LOWER(label) LIKE '%high sensitivity%'))
  )
),

troponin_measurements AS (
  -- join labevents to troponin item definitions, keep numeric results and prefer ng units (or NULL unit)
  SELECT
    le.subject_id,
    le.labevent_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    le.valueuom,
    d.label
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_items d
    ON le.itemid = d.itemid
  WHERE le.valuenum IS NOT NULL
    -- prefer ng units or unspecified unit; remove or modify if you'd like a strict unit filter
    AND (le.valueuom IS NULL OR LOWER(le.valueuom) LIKE '%ng%')
),

first_troponin_per_patient AS (
  -- pick the earliest troponin measurement per patient
  SELECT
    tm.subject_id,
    tm.labevent_id,
    tm.hadm_id,
    tm.charttime,
    tm.valuenum,
    tm.valueuom,
    tm.label,
    ROW_NUMBER() OVER (PARTITION BY tm.subject_id ORDER BY tm.charttime, tm.labevent_id) AS rn
  FROM troponin_measurements tm
  JOIN female_patients fp
    ON tm.subject_id = fp.subject_id
)

SELECT
  CASE
    WHEN valuenum < 0.014 THEN 'Normal (<0.014 ng/mL)'
    WHEN valuenum >= 0.014 AND valuenum < 0.04 THEN 'Borderline (0.014–<0.04)'
    WHEN valuenum >= 0.04 THEN 'Myocardial Injury (>=0.04)'
    ELSE 'Uncategorized'
  END AS troponin_category,
  COUNT(*) AS patient_count
FROM first_troponin_per_patient
WHERE rn = 1
GROUP BY troponin_category
ORDER BY
  CASE troponin_category
    WHEN 'Normal (<0.014 ng/mL)' THEN 1
    WHEN 'Borderline (0.014–<0.04)' THEN 2
    WHEN 'Myocardial Injury (>=0.04)' THEN 3
    ELSE 4
  END;