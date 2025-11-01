WITH 
  -- Filter patients and admissions
  patients_admissions AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 50 AND 60
  ),

  -- Filter admissions with primary ischemic stroke diagnosis
  ischemic_stroke_admissions AS (
    SELECT 
      hadm_id,
      admittime,
      dischtime
    FROM 
      patients_admissions
    WHERE 
      hadm_id IN (
        SELECT 
          hadm_id
        FROM 
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE 
          (icd_version = 9 AND icd_code BETWEEN '433' AND '436')
          OR (icd_version = 10 AND icd_code BETWEEN 'I63' AND 'I64')
        GROUP BY 
          hadm_id
        HAVING 
          MIN(seq_num) = 1  -- Primary diagnosis
      )
  )

-- Calculate 25th percentile hospital LOS
SELECT 
  APPROX_QUANTILES(TIMESTAMP_DIFF(dischtime, admittime, DAY), 4)[OFFSET(1)] AS los_25th_percentile
FROM 
  ischemic_stroke_admissions;