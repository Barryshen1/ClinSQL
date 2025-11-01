WITH first_hstn AS (
  SELECT
    l.hadm_id,
    l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
    ON l.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON l.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 59 AND 69
    AND LOWER(di.label) LIKE '%troponin%'
    AND LOWER(di.label) LIKE '%hs%'          -- target hs-TnT items
    AND LOWER(l.valueuom) LIKE '%ng/mL%'      -- units in ng/mL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) = 1
  AND l.valuenum > 0.014
)
SELECT
  -- min, 25th, 50th (median), 75th, max of the initial hs-TnT values
  q[OFFSET(0)] AS min_hs_tnT_ng_per_mL,
  q[OFFSET(1)] AS p25_hs_tnT_ng_per_mL,
  q[OFFSET(2)] AS p50_hs_tnT_ng_per_mL,
  q[OFFSET(3)] AS p75_hs_tnT_ng_per_mL,
  q[OFFSET(4)] AS max_hs_tnT_ng_per_mL
FROM (
  SELECT APPROX_QUANTILES(valuenum, 4) AS q
  FROM first_hstn
) AS t;