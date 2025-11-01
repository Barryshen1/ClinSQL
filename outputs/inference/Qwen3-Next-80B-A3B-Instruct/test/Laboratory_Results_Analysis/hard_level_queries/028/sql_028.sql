WITH ich_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, TRUE AS is_ich
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 74 AND 84
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432'))
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
    )
),

controls AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, FALSE AS is_ich
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 74 AND 84
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
      JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432'))
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
        )
    )
),

all_patients AS (
  SELECT * FROM ich_patients
  UNION ALL
  SELECT * FROM controls
),

lab_abnormal_72h AS (
  SELECT 
    l.subject_id,
    l.hadm_id,
    COUNT(DISTINCT l.itemid) AS num_distinct_abnormal_labs
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents l
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems dl ON l.itemid = dl.itemid
  JOIN all_patients adm ON l.subject_id = adm.subject_id AND l.hadm_id = adm.hadm_id
  WHERE l.charttime >= adm.admittime
    AND l.charttime <= adm.admittime + INTERVAL '72 hours'
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
    AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
  GROUP BY l.subject_id, l.hadm_id
),

patients_with_instability AS (
  SELECT 
    ap.subject_id,
    ap.hadm_id,
    ap.anchor_age,
    ap.admittime,
    ap.dischtime,
    ap.hospital_expire_flag,
    ap.is_ich,
    COALESCE(l.num_distinct_abnormal_labs, 0) AS instability_score
  FROM all_patients ap
  LEFT JOIN lab_abnormal_72h l ON ap.subject_id = l.subject_id AND ap.hadm_id = l.hadm_id
),

quintiles AS (
  SELECT 
    CASE WHEN is_ich THEN 'ICH' ELSE 'Control' END AS group_type,
    NTILE(5) OVER (ORDER BY instability_score) AS quintile,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
    hospital_expire_flag
  FROM patients_with_instability
)

SELECT 
  group_type,
  quintile,
  AVG(los_days) AS mean_los_days,
  AVG(hospital_expire_flag) AS mortality_rate
FROM quintiles
GROUP BY group_type, quintile
ORDER BY group_type, quintile;