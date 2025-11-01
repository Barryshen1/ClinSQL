WITH 
  -- Filter patients and admissions
  filtered_admissions AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 59 AND 69
  ),

  -- Identify heart failure admissions
  heart_failure_admissions AS (
    SELECT 
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      icd_code LIKE '428%'
  ),

  -- ICU stay durations
  icu_stay_durations AS (
    SELECT 
      i.hadm_id,
      TIMESTAMP_DIFF(i.outtime, i.intime, DAY) AS icu_stay_days
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` i
  ),

  -- Radiography/CT procedures
  radiography_procedures AS (
    SELECT 
      p.hadm_id,
      COUNT(*) AS radiography_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON 
      p.icd_code = d.icd_code
    WHERE 
      d.long_title LIKE '%Radiography%' OR d.long_title LIKE '%CT%'
    GROUP BY 
      p.hadm_id
  ),

  -- Combine admissions with radiography counts and ICU stay durations
  combined_data AS (
    SELECT 
      fa.hadm_id,
      COALESCE(isd.icu_stay_days, 0) AS icu_stay_days,
      CASE 
        WHEN COALESCE(isd.icu_stay_days, 0) BETWEEN 1 AND 4 THEN '1-4 days'
        WHEN COALESCE(isd.icu_stay_days, 0) BETWEEN 5 AND 8 THEN '5-8 days'
        ELSE 'Outside range'
      END AS icu_stay_group,
      COALESCE(rp.radiography_count, 0) AS radiography_count
    FROM 
      filtered_admissions fa
    JOIN 
      heart_failure_admissions hfa ON fa.hadm_id = hfa.hadm_id
    LEFT JOIN 
      icu_stay_durations isd ON fa.hadm_id = isd.hadm_id
    LEFT JOIN 
      radiography_procedures rp ON fa.hadm_id = rp.hadm_id
  )

-- Calculate percentiles
SELECT 
  icu_stay_group,
  APPROX_QUANTILES(radiography_count, 0.25)[OFFSET(0)] AS p25,
  APPROX_QUANTILES(radiography_count, 0.5)[OFFSET(0)] AS p50,
  APPROX_QUANTILES(radiography_count, 0.75)[OFFSET(0)] AS p75
FROM 
  combined_data
WHERE 
  icu_stay_group IN ('1-4 days', '5-8 days')
GROUP BY 
  icu_stay_group;