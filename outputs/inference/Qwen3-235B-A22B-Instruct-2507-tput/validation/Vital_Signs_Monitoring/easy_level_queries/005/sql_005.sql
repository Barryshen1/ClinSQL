SELECT
  APPROX_QUANTILES(valuenum, 1000)[OFFSET(750)] AS systolic_bp_75th_percentile
FROM
  `physionet-data.mimiciv_3_1_hosp`.patients p
JOIN
  `physionet-data.mimiciv_3_1_icu`.chartevents ce
  ON p.subject_id = ce.subject_id
JOIN
  `physionet-data.mimiciv_3_1_icu`.d_items di
  ON ce.itemid = di.itemid
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 59 AND 69
  AND LOWER(di.label) IN ('nibp systolic', 'arterial bp systolic')
  AND ce.valuenum IS NOT NULL
  AND ce.valuenum > 0  -- Exclude non-physiological values;