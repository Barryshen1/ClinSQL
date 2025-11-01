WITH 
  -- Filter and calculate medication complexity
  patients_with_stroke AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      p.anchor_age,
      COUNT(DISTINCT pnd.drug) AS unique_drugs
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.prescriptions` pnd ON a.hadm_id = pnd.hadm_id
    WHERE 
      p.anchor_age BETWEEN 89 AND 99
      AND p.gender = 'M'
      AND a.dischtime IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
        WHERE di.hadm_id = a.hadm_id AND dd.long_title LIKE '%Hemorrhagic stroke%'
      )
    GROUP BY 
      a.subject_id, a.hadm_id, a.admittime, a.dischtime, p.anchor_age
  ),

  -- Calculate quintiles of medication complexity
  patients_with_quintile AS (
    SELECT 
      subject_id,
      hadm_id,
      admittime,
      dischtime,
      anchor_age,
      unique_drugs,
      NTILE(5) OVER (ORDER BY unique_drugs) AS quintile
    FROM 
      patients_with_stroke
  ),

  -- Calculate outcomes
  outcomes AS (
    SELECT 
      pwq.quintile,
      TIMESTAMP_DIFF(pwq.dischtime, pwq.admittime, DAY) AS los,
      IF(a.hospital_expire_flag = 1, 1, 0) AS inpatient_mortality,
      CASE 
        WHEN EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
          WHERE a2.subject_id = pwq.subject_id 
          AND a2.admittime BETWEEN pwq.dischtime AND TIMESTAMP_ADD(pwq.dischtime, INTERVAL 30 DAY)
        ) THEN 1
        ELSE 0
      END AS readmitted_within_30_days
    FROM 
      patients_with_quintile pwq
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a ON pwq.hadm_id = a.hadm_id
  )

-- Group by quintile and calculate statistics
SELECT 
  quintile,
  AVG(los) AS avg_los,
  AVG(inpatient_mortality) AS inpatient_mortality_rate,
  AVG(readmitted_within_30_days) AS thirty_day_readmission_rate
FROM 
  outcomes
GROUP BY 
  quintile;