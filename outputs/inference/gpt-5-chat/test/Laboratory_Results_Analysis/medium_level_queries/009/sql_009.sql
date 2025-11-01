WITH hs_tnt AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum AS hs_tnt_value,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON le.hadm_id = adm.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 59 AND 69
    AND LOWER(di.label) LIKE '%troponin%high%sens%'
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
),
first_hs_tnt AS (
  SELECT
    subject_id,
    hadm_id,
    hs_tnt_value
  FROM hs_tnt
  WHERE rn = 1
    AND hs_tnt_value > 0.014
)
SELECT
  arr[OFFSET(0)] AS min_hs_tnt,
  arr[OFFSET(1)] AS p25_hs_tnt,
  arr[OFFSET(2)] AS median_hs_tnt,
  arr[OFFSET(3)] AS p75_hs_tnt,
  arr[OFFSET(4)] AS max_hs_tnt
FROM (
  SELECT APPROX_QUANTILES(hs_tnt_value, 4) AS arr
  FROM first_hs_tnt
);