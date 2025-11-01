WITH first_hstnt AS (
  SELECT
    le.hadm_id,
    le.valuenum,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents le
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON le.itemid = dl.itemid
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON le.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND LOWER(dl.label) IN (
      'high sensitivity troponin t',
      'hs-tnt',
      'troponin t, high sensitivity',
      'hs troponin t',
      'high sensitivity troponin t (ng/ml)'
    )
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0.014
)
SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS p75,
  MIN(valuenum) AS min_value,
  MAX(valuenum) AS max_value
FROM
  first_hstnt
WHERE
  rn = 1;