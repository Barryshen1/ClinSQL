WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING(subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      USING(subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND d.icd_version = 10
    AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')
),
hs_tnt_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%hs troponin t%'
),
first_hs_tnt AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER(PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN hs_tnt_items hi
      ON le.itemid = hi.itemid
)
SELECT
  CASE
    WHEN ft.valuenum <= 14 THEN 'normal'
    WHEN ft.valuenum > 14 AND ft.valuenum <= 52 THEN 'borderline'
    WHEN ft.valuenum > 52 THEN 'myocardial injury'
    ELSE 'unknown'
  END AS category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1) AS pct
FROM
  cohort c
  JOIN first_hs_tnt ft
    ON c.subject_id = ft.subject_id
    AND c.hadm_id    = ft.hadm_id
    AND ft.rn = 1
GROUP BY
  category
ORDER BY
  category;