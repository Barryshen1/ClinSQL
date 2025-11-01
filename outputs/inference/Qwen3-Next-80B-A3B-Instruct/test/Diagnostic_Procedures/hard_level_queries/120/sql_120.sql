WITH upper_gi_bleed_admissions AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE LOWER(d_icd.long_title) LIKE LOWER('%upper gastrointestinal hemorrhage%')
     OR LOWER(d_icd.long_title) LIKE LOWER('%gastric hemorrhage%')
     OR LOWER(d_icd.long_title) LIKE LOWER('%esophageal hemorrhage%')
     OR LOWER(d_icd.long_title) LIKE LOWER('%duodenal hemorrhage%')
     OR LOWER(d_icd.long_title) LIKE LOWER('%peptic ulcer hemorrhage%')
     OR LOWER(d_icd.long_title) LIKE LOWER('%upper GI bleeding%')
     OR LOWER(d_icd.long_title) LIKE LOWER('%hematemesis%')
     OR LOWER(d_icd.long_title) LIKE LOWER('%melena%')
     OR d.icd_code IN ('K25', 'K26', 'K27', 'K28', 'K22.0', 'K22.1', 'K22.2', 'K22.3', 'K22.4', 'K22.5', 'K22.6', 'K22.7', 'K22.8', 'K22.9')
     AND d.icd_version = 10
),
first_icu_stay AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN upper_gi_bleed_admissions u ON i.hadm_id = u.hadm_id
),
filtered_patients AS (
  SELECT 
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.outtime,
    f.los,
    p.gender,
    p.anchor_age,
    u.hospital_expire_flag
  FROM first_icu_stay f
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON f.subject_id = p.subject_id
  JOIN upper_gi_bleed_admissions u ON f.hadm_id = u.hadm_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 74 AND 84
    AND f.rn = 1
),
procedure_count_72h AS (
  SELECT 
    fp.subject_id,
    fp.hadm_id,
    fp.stay_id,
    COUNT(*) AS procedure_count_72h
  FROM filtered_patients fp
  LEFT JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe 
    ON fp.stay_id = pe.stay_id 
    AND pe.starttime >= fp.intime 
    AND pe.starttime <= TIMESTAMP_ADD(fp.intime, INTERVAL 72 HOUR)
  GROUP BY fp.subject_id, fp.hadm_id, fp.stay_id
),
final_data AS (
  SELECT 
    fp.subject_id,
    fp.hadm_id,
    fp.hospital_expire_flag,
    fp.los AS hospital_los_days,
    COALESCE(pc.procedure_count_72h, 0) AS procedure_count_72h,
    NTILE(4) OVER (ORDER BY COALESCE(pc.procedure_count_72h, 0)) AS quartile
  FROM filtered_patients fp
  LEFT JOIN procedure_count_72h pc ON fp.stay_id = pc.stay_id
)
SELECT 
  quartile,
  AVG(procedure_count_72h) AS mean_procedure_count,
  AVG(hospital_los_days) AS mean_hospital_los_days,
  AVG(hospital_expire_flag) AS in_hospital_mortality
FROM final_data
GROUP BY quartile
ORDER BY quartile;