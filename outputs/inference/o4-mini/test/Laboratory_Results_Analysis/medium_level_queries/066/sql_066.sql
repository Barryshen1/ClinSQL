WITH chest_pain_adms AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
     AND a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND LOWER(dd.long_title) LIKE '%chest pain%'
),
hs_tnt_items AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
    OR LOWER(category) LIKE '%troponin%'
),
first_hs_tnt AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.valuenum AS val,
    ROW_NUMBER() OVER (PARTITION BY ce.hadm_id ORDER BY ce.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` ce
    JOIN hs_tnt_items i
      ON ce.itemid = i.itemid
    JOIN chest_pain_adms c
      ON ce.subject_id = c.subject_id
     AND ce.hadm_id = c.hadm_id
  WHERE
    ce.valuenum IS NOT NULL
)
SELECT
  category,
  COUNT(*)                                    AS n,
  100 * COUNT(*) / SUM(COUNT(*)) OVER ()      AS pct,
  AVG(val)                                    AS mean,
  APPROX_QUANTILES(val, 4)[OFFSET(1)]         AS q1,
  APPROX_QUANTILES(val, 4)[OFFSET(2)]         AS median,
  APPROX_QUANTILES(val, 4)[OFFSET(3)]         AS q3,
  APPROX_QUANTILES(val, 4)[OFFSET(3)]
    - APPROX_QUANTILES(val, 4)[OFFSET(1)]     AS iqr
FROM (
  SELECT
    val,
    CASE
      WHEN val < 14 THEN 'normal'
      WHEN val <= 52 THEN 'borderline'
      ELSE 'myocardial injury'
    END AS category
  FROM first_hs_tnt
  WHERE rn = 1
)
GROUP BY
  category
ORDER BY
  category;