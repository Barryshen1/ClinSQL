WITH baseline_cr AS (
  -- Calculate baseline creatinine (min Cr in 48h pre-ICU or 0.7 default)
  SELECT 
    icu.subject_id,
    icu.stay_id,
    icu.intime,
    COALESCE(MIN(CASE WHEN labs.charttime < icu.intime 
                      AND labs.charttime >= TIMESTAMP_SUB(icu.intime, INTERVAL 48 HOUR)
                      THEN labs.valuenum END), 0.7) AS baseline_cr
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON 
    icu.subject_id = pat.subject_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` labs
  ON 
    icu.subject_id = labs.subject_id
    AND labs.hadm_id = icu.hadm_id
    AND labs.itemid = 50912  -- Serum Creatinine
    AND labs.valuenum IS NOT NULL
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 48 AND 58
  GROUP BY 
    icu.subject_id, icu.stay_id, icu.intime
),
aki_stays AS (
  SELECT 
    icu.stay_id,
    icu.los,
    base.baseline_cr,
    MAX(CASE WHEN labs.itemid = 50912 
             AND labs.charttime >= icu.intime 
             AND labs.charttime <= TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)  -- KDIGO 48h window for AKI
             AND labs.valuenum IS NOT NULL 
             THEN labs.valuenum END) AS max_cr
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN 
    baseline_cr base
  ON 
    icu.stay_id = base.stay_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` labs
  ON 
    icu.subject_id = labs.subject_id 
    AND icu.hadm_id = labs.hadm_id
    AND labs.itemid = 50912  -- Serum Creatinine
    AND labs.valuenum IS NOT NULL
  GROUP BY 
    icu.stay_id, icu.los, base.baseline_cr
  HAVING 
    max_cr >= 1.5 * baseline_cr  -- Relative threshold (1.5x baseline within 48h)
)
SELECT 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY EXTRACT(DAY FROM los)) AS p25_icu_los_days
FROM 
  aki_stays;