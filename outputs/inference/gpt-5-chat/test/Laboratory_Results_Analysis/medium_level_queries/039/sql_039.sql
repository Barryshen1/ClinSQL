WITH chest_pain_hadm AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.subject_id = dx.subject_id
   AND adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_dx
    ON dx.icd_code = d_dx.icd_code
   AND dx.icd_version = d_dx.icd_version
  WHERE LOWER(d_dx.long_title) LIKE '%chest pain%'
),
hs_tnt_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
index_hs_tnt AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN hs_tnt_items di
    ON l.itemid = di.itemid
  WHERE l.valuenum IS NOT NULL
),
first_hs_tnt AS (
  SELECT subject_id, hadm_id, valuenum,
         CASE
           WHEN valuenum <= 0.04 THEN 'Normal'
           WHEN valuenum <= 0.1 THEN 'Borderline'
           ELSE 'Injury'
         END AS category
  FROM (
    SELECT ih.subject_id, ih.hadm_id, ih.valuenum, ih.charttime,
           ROW_NUMBER() OVER (PARTITION BY ih.hadm_id ORDER BY ih.charttime ASC) AS rn
    FROM index_hs_tnt ih
  )
  WHERE rn = 1
),
cohort AS (
  SELECT p.subject_id, p.gender, p.anchor_age, f.hadm_id, f.valuenum, f.category
  FROM first_hs_tnt f
  JOIN chest_pain_hadm cph
    ON f.subject_id = cph.subject_id
   AND f.hadm_id = cph.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON f.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
)
SELECT
  category,
  COUNT(*) AS count_patients,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(valuenum), 4) AS mean_hs_tnt,
  ROUND( (APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] ), 4) AS median_hs_tnt,
  ROUND(
    APPROX_QUANTILES(valuenum, 100)[OFFSET(75)]
    - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)]
  , 4) AS iqr_hs_tnt
FROM cohort
GROUP BY category
ORDER BY
  CASE category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Injury' THEN 3
    ELSE 4
  END;