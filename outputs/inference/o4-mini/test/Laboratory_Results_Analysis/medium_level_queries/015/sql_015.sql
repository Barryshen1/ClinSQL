WITH acs_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON a.subject_id = dx.subject_id
     AND a.hadm_id    = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON dx.icd_code    = dicd.icd_code
     AND dx.icd_version = dicd.icd_version
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    LOWER(dicd.long_title) LIKE '%acute coronary syndrome%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
),
first_troponin AS (
  -- Get the first Troponin T measurement per admission
  SELECT
    le.subject_id,
    le.hadm_id,
    MIN(le.charttime) AS first_charttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
      ON le.itemid = li.itemid
  WHERE
    LOWER(li.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
  GROUP BY
    le.subject_id,
    le.hadm_id
),
first_troponin_values AS (
  -- Retrieve the value of that first measurement
  SELECT
    f.subject_id,
    f.hadm_id,
    le.valuenum AS first_val
  FROM
    first_troponin f
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON f.subject_id = le.subject_id
     AND f.hadm_id    = le.hadm_id
     AND f.first_charttime = le.charttime
)
SELECT
  quantiles[OFFSET(2)] AS median_ng_per_ml,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_ng_per_ml
FROM (
  SELECT
    APPROX_QUANTILES(ftv.first_val, 4) AS quantiles
  FROM
    acs_admissions acs
    JOIN first_troponin_values ftv
      ON acs.subject_id = ftv.subject_id
     AND acs.hadm_id    = ftv.hadm_id
  WHERE
    ftv.first_val > 0.01
) AS stats;