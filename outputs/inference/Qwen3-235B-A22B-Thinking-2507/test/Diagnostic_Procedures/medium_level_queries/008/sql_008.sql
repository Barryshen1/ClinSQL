WITH patient_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Calculate LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE a.dischtime IS NOT NULL  -- Only completed admissions
),
filtered_patients AS (
  SELECT 
    hadm_id,
    subject_id,
    los_days
  FROM patient_admissions
  WHERE gender = 'M'
    AND age_at_admission BETWEEN 58 AND 68
    AND los_days BETWEEN 1 AND 7  -- Only keep admissions in our LOS range
),
radiology_procedures AS (
  SELECT 
    hc.hadm_id,
    COUNT(*) AS num_radiology
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d 
    ON hc.hcpcs_cd = d.code
  WHERE d.category = 3  -- HCPCS category 3 = Radiology
  GROUP BY hc.hadm_id
),
admission_procedures AS (
  SELECT 
    fp.hadm_id,
    fp.subject_id,
    fp.los_days,
    COALESCE(rp.num_radiology, 0) AS num_radiology
  FROM filtered_patients fp
  LEFT JOIN radiology_procedures rp 
    ON fp.hadm_id = rp.hadm_id
)
SELECT 
  CASE 
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
    WHEN los_days BETWEEN 5 AND 7 THEN '5-7'
  END AS los_group,
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(*) AS admission_count,
  AVG(num_radiology) AS mean_radiology_procedures_per_admission
FROM admission_procedures
GROUP BY los_group
ORDER BY los_group;