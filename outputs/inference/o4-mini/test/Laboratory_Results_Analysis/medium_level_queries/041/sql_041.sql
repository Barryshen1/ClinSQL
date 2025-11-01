WITH male_middle_aged AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
),

acs_admissions AS (
  SELECT DISTINCT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%acute coronary syndrome%'
),

hs_troponin_events AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    le.ref_range_upper,
    di.label
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
      ON le.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%troponin t%'
    AND LOWER(di.label) LIKE '%high sensitivity%'
    AND le.valuenum IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND le.valuenum > le.ref_range_upper
),

initial_hs_troponin AS (
  SELECT
    he.subject_id,
    he.hadm_id,
    he.valuenum AS initial_value
  FROM (
    SELECT
      he.*,
      ROW_NUMBER() OVER (PARTITION BY he.hadm_id ORDER BY he.charttime) AS rn
    FROM
      hs_troponin_events he
    -- only keep patients who are male, middle‐aged, with ACS admission
    JOIN male_middle_aged m
      ON he.subject_id = m.subject_id
    JOIN acs_admissions acs
      ON he.hadm_id = acs.hadm_id
  ) he
  WHERE
    he.rn = 1
)

SELECT
  -- Extract approximate quartiles: [min, Q1, median, Q3, max]
  quantiles[OFFSET(2)] AS median_ng_per_ml,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_ng_per_ml,
  quantiles[OFFSET(1)] AS q1_ng_per_ml,
  quantiles[OFFSET(3)] AS q3_ng_per_ml
FROM (
  SELECT
    APPROX_QUANTILES(initial_value, 4) AS quantiles
  FROM
    initial_hs_troponin
);