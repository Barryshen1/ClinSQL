WITH filtered_stays AS (
  SELECT i.stay_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE pe.stay_id = i.stay_id
        AND pe.itemid = 225792  -- Endotracheal Intubation
    )
)
SELECT
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) - 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum) AS iqr
FROM (
  SELECT ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN filtered_stays fs 
    ON ce.stay_id = fs.stay_id
  WHERE ce.itemid IN (220050, 220179)
    AND ce.charttime BETWEEN fs.intime AND TIMESTAMP_ADD(fs.intime, INTERVAL 6 HOUR)
    AND ce.valuenum IS NOT NULL
) AS bp_values;