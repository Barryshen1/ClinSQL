WITH resp_rate_first AS (
  SELECT
    ce.stay_id,
    ce.valuenum AS respiratory_rate,
    ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON ce.stay_id = icu.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON icu.subject_id = p.subject_id
  WHERE
    LOWER(di.label) = 'respiratory rate'
    AND ce.valuenum IS NOT NULL
    AND p.anchor_age BETWEEN 51 AND 61
    AND p.gender = 'F'
    AND ce.charttime >= icu.intime
)
SELECT
  APPROX_QUANTILES(respiratory_rate, 100)[OFFSET(25)] AS resp_rate_25th_percentile
FROM resp_rate_first
WHERE rn = 1;