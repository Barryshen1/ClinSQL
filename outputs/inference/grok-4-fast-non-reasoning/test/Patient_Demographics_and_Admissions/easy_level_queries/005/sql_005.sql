WITH dialysis_patients AS (
  SELECT DISTINCT
    ie.subject_id,
    ie.stay_id
  FROM 
    `physionet-data.mimiciv_3_1_icu.inputevents` ie
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON 
    ie.itemid = di.itemid
  WHERE 
    di.label IN ('Hemodialysis', 'CRRT machine', 'Hemofiltration')  -- Common dialysis itemids: 225798, 220735, 228401
    AND ie.amount > 0
),

first_icu_stays AS (
  SELECT 
    icu.subject_id,
    icu.los
  FROM (
    SELECT 
      icu.subject_id,
      icu.stay_id,
      icu.los,
      ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS rn
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      icu.subject_id = p.subject_id
    INNER JOIN 
      dialysis_patients dp
    ON 
      icu.subject_id = dp.subject_id 
      AND icu.stay_id = dp.stay_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 77 AND 87
      AND icu.los > 0
  ) ranked
  WHERE rn = 1
)

SELECT 
  PERCENTILE_CONT(0.75, OVER ()) - PERCENTILE_CONT(0.25, OVER ()) AS iqr_los_days
FROM first_icu_stays;