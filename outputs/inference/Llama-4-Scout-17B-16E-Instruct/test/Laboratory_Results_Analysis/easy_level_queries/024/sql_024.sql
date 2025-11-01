WITH 
  -- Identify sepsis admissions
  sepsis_admissions AS (
    SELECT 
      a.hadm_id,
      a.subject_id,
      p.gender,
      p.anchor_age,
      a.admittime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON 
      a.hadm_id = d.hadm_id
    WHERE 
      d.icd_code IN ('038', '995.91', '995.92')  -- Sepsis ICD-9 codes
      AND p.gender = 'M'  -- Male patients
  ),

  -- Find admission platelet count
  platelet_counts AS (
    SELECT 
      le.hadm_id,
      le.valuenum AS platelet_count,
      ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
    FROM 
      `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON 
      le.itemid = dl.itemid
    WHERE 
      dl.label = 'PLATELET COUNT'  -- Platelet count lab item
  )

-- Calculate SD of admission platelet count among male sepsis admissions
SELECT 
  STDDEV(pc.platelet_count) AS sd_platelet_count
FROM 
  sepsis_admissions sa
JOIN 
  platelet_counts pc
ON 
  sa.hadm_id = pc.hadm_id
  AND pc.rn = 1
WHERE 
  sa.anchor_age >= 88;  -- Filter for patients aged 88 or older;