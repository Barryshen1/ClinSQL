WITH 
-- Identify patients with PE
pe_patients AS (
  SELECT DISTINCT 
    d.subject_id, 
    d.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE 
    d.icd_code LIKE 'I26%' 
    AND d.icd_version = 9
),

-- Filter patients by age and gender
filtered_patients AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 64 AND 74
),

-- Combine PE patients with age and gender filter
pe_filtered_patients AS (
  SELECT 
    pp.subject_id, 
    pp.hadm_id, 
    fp.anchor_age, 
    fp.gender
  FROM 
    pe_patients pp
  JOIN 
    filtered_patients fp 
      ON pp.subject_id = fp.subject_id
),

-- Medication administration within first 24 hours
medications AS (
  SELECT 
    pfp.hadm_id, 
    COUNT(DISTINCT p.drug) AS distinct_meds
  FROM 
    pe_filtered_patients pfp
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
      ON pfp.hadm_id = p.hadm_id
  WHERE 
    p.starttime BETWEEN (SELECT admittime FROM `physionet-data.mimiciv_3_1_hosp.admissions` a WHERE a.hadm_id = pfp.hadm_id)
    AND TIMESTAMP_ADD((SELECT admittime FROM `physionet-data.mimiciv_3_1_hosp.admissions` a WHERE a.hadm_id = pfp.hadm_id), INTERVAL 1 DAY)
  GROUP BY 
    pfp.hadm_id
),

-- Calculate tertiles of medication complexity
medication_tertiles AS (
  SELECT 
    hadm_id, 
    distinct_meds,
    NTILE(3) OVER (ORDER BY distinct_meds) AS med_tertile
  FROM 
    medications
),

-- Calculate LOS, mortality, and 30-day readmission
outcomes AS (
  SELECT 
    mt.hadm_id, 
    mt.med_tertile,
    mt.distinct_meds,
    a.dischtime - a.admittime AS los,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 1 
      ELSE 0 
    END AS mortality,
    CASE 
      WHEN EXISTS (
        SELECT 
          1 
        FROM 
          `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE 
          a2.subject_id = a.subject_id 
          AND a2.admittime BETWEEN a.dischtime + INTERVAL 1 DAY 
          AND a.dischtime + INTERVAL 31 DAY
      ) THEN 1 
      ELSE 0 
    END AS readmitted
  FROM 
    medication_tertiles mt
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON mt.hadm_id = a.hadm_id
)

-- Final aggregation
SELECT 
  med_tertile,
  COUNT(DISTINCT hadm_id) AS admissions,
  MIN(distinct_meds) AS min_meds,
  MAX(distinct_meds) AS max_meds,
  AVG(los) AS avg_los,
  SUM(mortality) / COUNT(DISTINCT hadm_id) AS mortality_rate,
  SUM(readmitted) / COUNT(DISTINCT hadm_id) AS readmission_rate
FROM 
  outcomes
GROUP BY 
  med_tertile
ORDER BY 
  med_tertile;