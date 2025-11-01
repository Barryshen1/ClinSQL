WITH 
  -- Filter patients of interest
  patients_of_interest AS (
    SELECT 
      p.subject_id, 
      p.anchor_age, 
      p.gender,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 82 AND 92
  ),

  -- Identify ICU stays for patients of interest with acute respiratory failure
  icu_stays AS (
    SELECT 
      i.stay_id,
      i.hadm_id,
      i.subject_id,
      i.intime,
      i.outtime
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN 
      patients_of_interest p 
        ON i.hadm_id = p.hadm_id
    WHERE 
      -- Assuming acute respiratory failure is coded in diagnoses
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = i.hadm_id 
          AND d.icd_code LIKE '518.2'  -- Acute respiratory failure
      )
  ),

  -- Calculate MAP and HR burden
  vital_signs AS (
    SELECT 
      cv.subject_id,
      cv.hadm_id,
      cv.stay_id,
      cv.charttime,
      cv.itemid,
      cv.valuenum,
      cv.valueuom
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` cv
    WHERE 
      cv.itemid IN (220050, 220179)  -- MAP and HR
  ),

  -- Calculate burden of instability (MAP < 65, HR > 100)
  instability_burden AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      charttime,
      itemid,
      valuenum,
      valueuom,
      CASE 
        WHEN itemid = 220050 AND valuenum < 65 THEN 1
        WHEN itemid = 220179 AND valuenum > 100 THEN 1
        ELSE 0
      END AS instability
    FROM 
      vital_signs
  ),

  -- Calculate composite instability score (first 72 hours)
  instability_score AS (
    SELECT 
      ib.subject_id,
      ib.hadm_id,
      ib.stay_id,
      SUM(ib.instability) AS burden
    FROM 
      instability_burden ib
    JOIN 
      icu_stays is_stay 
        ON ib.subject_id = is_stay.subject_id
        AND ib.hadm_id = is_stay.hadm_id
        AND ib.stay_id = is_stay.stay_id
    WHERE 
      ib.charttime BETWEEN is_stay.intime AND TIMESTAMP_ADD(is_stay.intime, INTERVAL 3 HOUR)
    GROUP BY 
      ib.subject_id, ib.hadm_id, ib.stay_id
  ),

  -- Calculate ICU LOS and mortality
  icu_outcomes AS (
    SELECT 
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      TIMESTAMP_DIFF(i.outtime, i.intime, DAY) AS icu_los,
      CASE 
        WHEN p.deathtime IS NOT NULL THEN 1
        ELSE 0
      END AS mortality
    FROM 
      icu_stays i
    JOIN 
      patients_of_interest p 
        ON i.hadm_id = p.hadm_id
  )

-- Final query to report p25/median/p75, IQR of composite instability score
-- and compare average burdens, ICU LOS, and mortality
SELECT 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY burden) AS p25,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY burden) AS median,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY burden) AS p75,
  AVG(burden) AS avg_burden,
  AVG(icu_los) AS avg_icu_los,
  AVG(mortality) AS avg_mortality
FROM 
  instability_score
  JOIN icu_outcomes 
    ON instability_score.subject_id = icu_outcomes.subject_id
    AND instability_score.hadm_id = icu_outcomes.hadm_id
    AND instability_score.stay_id = icu_outcomes.stay_id;