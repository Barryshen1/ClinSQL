WITH ami_admissions AS (
  -- Identify admissions with AMI diagnosis
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%acute myocardial infarction%'
),

female_patients AS (
  -- Filter female patients aged 64–74
  SELECT
    subject_id
  FROM
    physionet-data.mimiciv_3_1_hosp.patients
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 64 AND 74
),

troponin_labs AS (
  -- Get first troponin T lab per admission
  SELECT
    l.hadm_id,
    MIN(l.charttime) AS first_charttime
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%troponin%t%'
    AND l.valuenum IS NOT NULL
  GROUP BY
    l.hadm_id
),

first_troponin_values AS (
  -- Get the first numeric troponin value per admission
  SELECT
    l.hadm_id,
    l.valuenum AS troponin_value
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    troponin_labs t
    ON l.hadm_id = t.hadm_id AND l.charttime = t.first_charttime
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%troponin%t%'
    AND l.valuenum IS NOT NULL
),

eligible_admissions AS (
  -- Join AMI admissions with female patients and first troponin values
  SELECT
    a.hadm_id,
    t.troponin_value
  FROM
    ami_admissions a
  JOIN
    female_patients p
    ON a.subject_id = p.subject_id
  JOIN
    first_troponin_values t
    ON a.hadm_id = t.hadm_id
),

troponin_categories AS (
  SELECT
    hadm_id,
    CASE
      WHEN troponin_value <= 0.014 THEN 'Normal'
      WHEN troponin_value <= 0.052 THEN 'Borderline'
      ELSE 'Myocardial Injury'
    END AS category
  FROM
    eligible_admissions
)

SELECT
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM
  troponin_categories
GROUP BY
  category
ORDER BY
  CASE category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    ELSE 3
  END;