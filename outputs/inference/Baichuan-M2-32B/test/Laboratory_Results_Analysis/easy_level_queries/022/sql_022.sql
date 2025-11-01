WITH peak_pH_per_stay AS (
  SELECT 
    i.stay_id,
    MAX(c.valuenum) AS peak_pH
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents c
    ON i.subject_id = c.subject_id
    AND i.hadm_id = c.hadm_id
    AND i.stay_id = c.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON i.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) = 63
    AND c.itemid = 378
    AND c.valuenum IS NOT NULL
  GROUP BY i.stay_id
)
SELECT 
  APPROX_QUANTILES(peak_pH, 100)[SAFE_OFFSET(74)] - APPROX_QUANTILES(peak_pH, 100)[SAFE_OFFSET(24)] AS iqr
FROM peak_pH_per_stay;