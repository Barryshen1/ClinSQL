WITH hf_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS length_of_stay_days
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND dicd.long_title LIKE '%heart failure%'
),
medication_complexity AS (
  SELECT 
    hp.subject_id,
    hp.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_count_7day
  FROM 
    hf_patients hp
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.prescriptions pr
    ON hp.subject_id = pr.subject_id
  WHERE 
    pr.starttime >= hp.admittime - INTERVAL 7 DAY
    AND pr.starttime <= hp.admittime
  GROUP BY 
    hp.subject_id, hp.hadm_id
),
quintiles AS (
  SELECT 
    mc.subject_id,
    mc.hadm_id,
    mc.med_count_7day,
    NTILE(5) OVER (ORDER BY mc.med_count_7day) AS quintile
  FROM 
    medication_complexity mc
),
readmission AS (
  SELECT 
    a1.subject_id,
    a1.hadm_id,
    CASE 
      WHEN a2.hadm_id IS NOT NULL THEN 1 
      ELSE 0 
    END AS readmission_30d
  FROM 
    hf_patients a1
  LEFT JOIN 
    physionet-data.mimiciv_3_1_hosp.admissions a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= a1.dischtime + INTERVAL 30 DAY
),
final_analysis AS (
  SELECT 
    q.quintile,
    COUNT(*) AS patient_count,
    MIN(q.med_count_7day) AS min_score,
    MAX(q.med_count_7day) AS max_score,
    AVG(h.length_of_stay_days) AS mean_los_days,
    AVG(CAST(h.hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality,
    AVG(CAST(r.readmission_30d AS FLOAT64)) AS thirty_day_readmission
  FROM 
    quintiles q
  INNER JOIN 
    hf_patients h
    ON q.subject_id = h.subject_id AND q.hadm_id = h.hadm_id
  INNER JOIN 
    readmission r
    ON q.subject_id = r.subject_id AND q.hadm_id = r.hadm_id
  GROUP BY 
    q.quintile
  ORDER BY 
    q.quintile
)
SELECT 
  quintile,
  patient_count,
  min_score,
  max_score,
  ROUND(mean_los_days, 2) AS mean_los_days,
  ROUND(in_hospital_mortality, 4) AS in_hospital_mortality,
  ROUND(thirty_day_readmission, 4) AS thirty_day_readmission
FROM 
  final_analysis;