WITH chest_pain_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
      ON d.icd_code = ddi.icd_code
     AND d.icd_version = ddi.icd_version
  WHERE
    LOWER(ddi.long_title) LIKE '%chest pain%'
),
eligible_patients AS (
  SELECT
    c.subject_id,
    c.hadm_id
  FROM
    chest_pain_admissions c
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON c.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
),
troponin_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%troponin i%'
),
first_elevated_troponin AS (
  SELECT
    ft.subject_id,
    ft.hadm_id,
    ft.valuenum
  FROM (
    SELECT
      e.subject_id,
      e.hadm_id,
      e.valuenum,
      e.ref_range_upper,
      ROW_NUMBER() OVER (
        PARTITION BY e.subject_id, e.hadm_id
        ORDER BY e.charttime
      ) AS rn
    FROM
      eligible_patients ep
      JOIN `physionet-data.mimiciv_3_1_hosp.labevents` e
        ON ep.subject_id = e.subject_id
       AND ep.hadm_id = e.hadm_id
      JOIN troponin_items ti
        ON e.itemid = ti.itemid
    WHERE
      e.valuenum IS NOT NULL
  ) ft
  WHERE
    ft.rn = 1
    AND ft.valuenum > ft.ref_range_upper
)
SELECT
  quantiles[SAFE_OFFSET(1)] AS p25,
  quantiles[SAFE_OFFSET(2)] AS p50,
  quantiles[SAFE_OFFSET(3)] AS p75,
  quantiles[SAFE_OFFSET(0)] AS min_value,
  quantiles[SAFE_OFFSET(4)] AS max_value
FROM (
  SELECT
    APPROX_QUANTILES(valuenum, 4) AS quantiles
  FROM
    first_elevated_troponin
);