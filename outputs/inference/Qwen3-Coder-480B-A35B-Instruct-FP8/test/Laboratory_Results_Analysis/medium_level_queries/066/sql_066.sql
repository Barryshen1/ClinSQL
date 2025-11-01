WITH chest_pain_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    p.anchor_age + DATE_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) AS age_at_admit
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
    LOWER(dd.long_title) LIKE '%chest pain%'
    AND p.gender = 'M'
    AND p.anchor_age + DATE_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) BETWEEN 39 AND 49
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
    LOWER(d.label) LIKE '%troponin t hs%'
    AND l.valuenum IS NOT NULL
),

initial_troponin AS (
  SELECT
    f.hadm_id,
    f.troponin_value,
    CASE
      WHEN f.troponin_value < 14 THEN 'Normal'
      WHEN f.troponin_value BETWEEN 14 AND 19 THEN 'Borderline'
      WHEN f.troponin_value >= 20 THEN 'Myocardial Injury'
    END AS troponin_category
  FROM
    first_troponin f
  WHERE
    f.rn = 1
),

category_stats AS (
  SELECT
    troponin_category,
    COUNT(*) AS n,
    AVG(troponin_value) AS mean_troponin,
    APPROX_QUANTILES(troponin_value, 4) AS quantiles
  FROM
    initial_troponin
  GROUP BY
    troponin_category
),

total_count AS (
  SELECT COUNT(*) AS total FROM initial_troponin
)

SELECT
  cs.troponin_category,
  cs.n,
  ROUND(100 * cs.n / tc.total, 2) AS percentage,
  ROUND(cs.mean_troponin, 2) AS mean_troponin,
  ROUND(cs.quantiles[ORDINAL(3)], 2) AS median_troponin,
  ROUND(cs.quantiles[ORDINAL(2)], 2) AS q1_troponin,
  ROUND(cs.quantiles[ORDINAL(4)], 2) AS q3_troponin,
  ROUND(cs.quantiles[ORDINAL(4)] - cs.quantiles[ORDINAL(2)], 2) AS iqr_troponin
FROM
  category_stats cs
CROSS JOIN
  total_count tc
ORDER BY
  CASE cs.troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial Injury' THEN 3
  END;