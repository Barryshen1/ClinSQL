SELECT
  APPROX_QUANTILES(valuenum, 1000)[OFFSET(750)] AS systolic_bp_75th_percentile
FROM (
  SELECT 
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ce.subject_id = p.subject_id
  WHERE 
    ce.itemid IN (220050, 220179)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND p.gender = 'F'
    AND (EXTRACT(YEAR FROM ce.charttime) - (p.anchor_year - p.anchor_age)) BETWEEN 59 AND 69
);