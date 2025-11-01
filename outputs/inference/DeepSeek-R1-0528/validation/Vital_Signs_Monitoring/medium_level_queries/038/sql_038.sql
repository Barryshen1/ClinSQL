WITH qualifying_stays AS (
  SELECT 
    ie.subject_id, 
    ie.stay_id, 
    ie.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM ie.intime) - (p.anchor_year - p.anchor_age) BETWEEN 66 AND 76
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      WHERE ce.subject_id = ie.subject_id
        AND ce.stay_id = ie.stay_id
        AND ce.itemid = 226732  -- Airway Type itemid
        AND ce.value = 'Endotracheal tube'
        AND ce.charttime BETWEEN ie.intime 
            AND DATETIME_ADD(ie.intime, INTERVAL 6 HOUR)
    )
)

SELECT 
  APPROX_QUANTILES(ce.valuenum, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(ce.valuenum, 100)[OFFSET(75)] AS q3,
  APPROX_QUANTILES(ce.valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(ce.valuenum, 100)[OFFSET(25)] AS iqr
FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
INNER JOIN qualifying_stays qs
  ON ce.subject_id = qs.subject_id
  AND ce.stay_id = qs.stay_id
WHERE ce.itemid IN (220050, 225312, 220179, 225309)  -- SBP itemids
  AND ce.valuenum IS NOT NULL
  AND ce.charttime BETWEEN qs.intime 
      AND DATETIME_ADD(qs.intime, INTERVAL 6 HOUR);