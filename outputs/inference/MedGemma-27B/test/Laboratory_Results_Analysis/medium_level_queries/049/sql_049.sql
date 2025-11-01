WITH TroponinData AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    le.value AS troponin_value,
    le.valueuom,
    dli.label AS troponin_label,
    dli.loinc_code,
    dli.ref_range_upper AS troponin_uln
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON le.subject_id = p.subject_id
  WHERE
    dli.label LIKE 'Troponin T%'
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
),
PercentileData AS (
  SELECT
    PERCENTILE_CONT(troponin_value, 0.25) AS p25,
    PERCENTILE_CONT(troponin_value, 0.50) AS p50,
    PERCENTILE_CONT(troponin_value, 0.75) AS p75,
    MIN(troponin_value) AS min_value,
    MAX(troponin_value) AS max_value,
    COUNT(DISTINCT subject_id) AS cohort_size
  FROM
    TroponinData
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 49 AND 59
    AND troponin_value > troponin_uln * 0.99 -- Assuming 99th percentile ULN is 0.99 * ULN
),
ULNData AS (
  SELECT
    AVG(troponin_uln) AS avg_uln
  FROM
    TroponinData
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 49 AND 59
)
SELECT
  pd.cohort_size,
  ud.avg_uln AS ULN,
  pd.p25,
  pd.p50,
  pd.p75,
  pd.min_value,
  pd.max_value
FROM
  PercentileData AS pd,
  ULNData AS ud;