WITH chest_pain_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND di.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%chest pain%'
),
initial_hs_tnt AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS hs_tnt_value,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin t%'
    AND LOWER(dl.label) LIKE '%sensitivity%'
    AND l.valuenum IS NOT NULL
),
categorized AS (
  SELECT
    cpa.subject_id,
    cpa.hadm_id,
    ih.hs_tnt_value,
    CASE
      WHEN ih.hs_tnt_value <= 14 THEN 'Normal'
      WHEN ih.hs_tnt_value > 14 AND ih.hs_tnt_value <= 50 THEN 'Borderline'
      WHEN ih.hs_tnt_value > 50 THEN 'Myocardial Injury'
      ELSE 'Unknown'
    END AS category
  FROM chest_pain_admissions cpa
  JOIN initial_hs_tnt ih
    ON cpa.hadm_id = ih.hadm_id
  WHERE ih.rn = 1
),
stats AS (
  SELECT
    category,
    COUNT(*) AS n_patients,
    AVG(hs_tnt_value) AS mean_hs_tnt,
    APPROX_QUANTILES(hs_tnt_value, 4) AS quartiles
  FROM categorized
  GROUP BY category
)
SELECT
  category,
  n_patients,
  ROUND(n_patients / SUM(n_patients) OVER() * 100, 2) AS pct_patients,
  ROUND(mean_hs_tnt, 2) AS mean_hs_tnt,
  ROUND(quartiles[OFFSET(2)], 2) AS median_hs_tnt,
  ROUND(quartiles[OFFSET(3)] - quartiles[OFFSET(1)], 2) AS iqr_hs_tnt
FROM stats
ORDER BY category;