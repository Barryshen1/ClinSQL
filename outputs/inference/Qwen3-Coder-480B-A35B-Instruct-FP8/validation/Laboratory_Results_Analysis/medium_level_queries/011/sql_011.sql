WITH chest_pain_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    p.anchor_age
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 61 AND 71
    AND LOWER(dd.long_title) = 'chest pain'
),
first_troponin AS (
  SELECT
    l.hadm_id,
    l.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%troponin t%'
    AND l.valuenum IS NOT NULL
    AND l.charttime IS NOT NULL
),
troponin_first_only AS (
  SELECT
    hadm_id,
    troponin_value
  FROM
    first_troponin
  WHERE
    rn = 1
),
categorized AS (
  SELECT
    hadm_id,
    CASE
      WHEN troponin_value < 14 THEN 'Normal'
      WHEN troponin_value BETWEEN 14 AND 19 THEN 'Borderline'
      WHEN troponin_value >= 20 THEN 'Myocardial Injury'
      ELSE 'Unknown'
    END AS troponin_category
  FROM
    troponin_first_only
)
SELECT
  troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM
  categorized
GROUP BY
  troponin_category
ORDER BY
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial Injury' THEN 3
    ELSE 4
  END;