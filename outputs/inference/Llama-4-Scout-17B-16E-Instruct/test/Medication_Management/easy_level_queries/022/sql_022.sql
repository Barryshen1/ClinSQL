WITH 
  -- Filter patients of interest
  patients_of_interest AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 59 AND 69
  ),
  
  -- Identify dihydropyridine CCB prescriptions and calculate their durations
  prescription_durations AS (
    SELECT 
      p.subject_id,
      p.hadm_id,
      p.starttime,
      p.stoptime,
      TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS prescription_duration_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN 
      patients_of_interest poi ON p.subject_id = poi.subject_id
    WHERE 
      LOWER(p.drug) LIKE '%calcium channel blocker%' OR 
      LOWER(p.drug) LIKE '%dihydropyridine%' OR 
      LOWER(p.drug) LIKE '%amlodipine%' OR 
      LOWER(p.drug) LIKE '%nifedipine%' OR 
      LOWER(p.drug) LIKE '%nicardipine%' OR 
      LOWER(p.drug) LIKE '%nimodipine%' OR 
      LOWER(p.drug) LIKE '%nisoldipine%' OR 
      LOWER(p.drug) LIKE '%felodipine%'
  )

SELECT 
  APPROX_QUANTILES(prescription_duration_days, 1000)[500] AS median_prescription_duration_days
FROM 
  prescription_durations;