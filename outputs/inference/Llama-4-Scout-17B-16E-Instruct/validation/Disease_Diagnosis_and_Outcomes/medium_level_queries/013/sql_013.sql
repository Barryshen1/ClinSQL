WITH 
  admissions_with_los AS (
    SELECT 
      a.hadm_id,
      a.subject_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag,
      TIMESTAMPDIFF(DAY, a.admittime, COALESCE(a.deathtime, a.dischtime)) AS los_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp`.admissions a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp`.patients p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      TIMESTAMPDIFF(YEAR, p.anchor_year, a.admittime) BETWEEN 80 AND 90
      AND p.gender = 'F'
      AND a.admission_location IN ('CARDIOLOGY', 'CCU', 'ICU', 'MICU', 'CVICU')
  ),
  categorized_admissions AS (
    SELECT 
      hadm_id,
      subject_id,
      admittime,
      dischtime,
      deathtime,
      hospital_expire_flag,
      los_days,
      CASE 
        WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
        WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
        WHEN los_days >= 8 THEN '>=8'
        ELSE 'Invalid'
      END AS los_category
    FROM 
      admissions_with_los
  ),
  filtered_admissions AS (
    SELECT 
      *
    FROM 
      categorized_admissions
    WHERE 
      los_category IN ('1-3', '4-7', '>=8')
  )

SELECT 
  los_category,
  COUNT(CASE WHEN hospital_expire_flag = 1 THEN hadm_id END) AS num_deaths,
  COUNT(hadm_id) AS total_patients,
  COUNT(CASE WHEN hospital_expire_flag = 1 THEN hadm_id END) / COUNT(hadm_id) AS mortality_rate,
  APPROX_QUANTILES(los_days, 100)[OFFSET(2.5)] AS lower_95_ci,
  APPROX_QUANTILES(los_days, 100)[OFFSET(97.5)] AS upper_95_ci,
  APPROX_MEDIAN(los_days) AS median_los
FROM 
  filtered_admissions
GROUP BY 
  los_category;