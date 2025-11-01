WITH female_icu_stays AS (
  SELECT 
    i.stay_id, 
    i.subject_id, 
    i.hadm_id, 
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
closest_abg_ph AS (
  SELECT 
    f.stay_id,
    l.valuenum AS ph_value,
    ROW_NUMBER() OVER (
      PARTITION BY f.stay_id
      ORDER BY ABS(DATETIME_DIFF(l.charttime, f.intime, SECOND)), 
               l.charttime DESC  -- Prefer post-admission if ties
    ) AS rn
  FROM female_icu_stays f
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON f.subject_id = l.subject_id
    AND f.hadm_id = l.hadm_id
  WHERE l.itemid = 50820  -- Arterial pH
    AND l.charttime 
      BETWEEN DATETIME_SUB(f.intime, INTERVAL 24 HOUR)
      AND DATETIME_ADD(f.intime, INTERVAL 6 HOUR)
    AND l.valuenum IS NOT NULL  -- Ensure numeric value
)
SELECT 
  APPROX_QUANTILES(ph_value, 100)[OFFSET(50)] AS median_ph
FROM closest_abg_ph
WHERE rn = 1;  -- Only the nearest measurement per stay;